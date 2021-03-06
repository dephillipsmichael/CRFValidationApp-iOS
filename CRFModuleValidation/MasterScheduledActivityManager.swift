//
//  MasterScheduledActivityManager.swift
//  JourneyPRO
//
//  Copyright © 2017 Sage Bionetworks. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// 1.  Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// 2.  Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation and/or
// other materials provided with the distribution.
//
// 3.  Neither the name of the copyright holder(s) nor the names of any contributors
// may be used to endorse or promote products derived from this software without
// specific prior written permission. No license is granted to the trademarks of
// the copyright holders even if such marks are included in this software.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

import Foundation
import BridgeSDK
import BridgeAppSDK
import ResearchUXFactory
import UserNotifications
import ResearchSuiteUI

enum ScheduleLoadState {
    case firstLoad
    case cachedLoad
    case fromServer
}

class MasterScheduledActivityManager: ScheduledActivityManager {
    
    static let shared = MasterScheduledActivityManager(delegate: nil)
    
    // Save a pointer to today's activities in case the paged group does not include them
    var scheduleSections: [ScheduleSection] = []
    
    let scheduleUpdatedNotificationName = Notification.Name("MasterScheduledActivityManager.scheduleUpdated")
    
    let studyDuration: DateComponents = {
        var studyDuration = DateComponents()
        studyDuration.day = 14
        return studyDuration
    }()
    
    var enrollment: Date = {
        return (UIApplication.shared.delegate as! AppDelegate).currentUser.createdOn.startOfDay()
    }()
    
    var startStudy: Date {
        return Calendar.gregorian.startOfDay(for: dayOne ?? enrollment)
    }
    
    var endStudy: Date {
        return self.startStudy.adding(studyDuration).endOfDay()
    }
    
    var scheduleAhead: Date {
        return Date().startOfDay().addingNumberOfDays(self.daysAhead + 1)
    }
    
    var dayOne: Date?
    
    // When true, the completion step for all scheduling tasks will be skipped
    var alwaysIgnoreTimingIntroductionStepForScheduling = false

    // When set, the user should be automatically sent to the screen to do these tasks
    // After this var is consumed, it should be set back to nil
    var deepLinkTaskGroup: TaskGroup?
    
    // When this contians an object, it will exist until the specific task it is
    // associated with becomes available, and then its closure will be invoked
    fileprivate var notifyAvailableTasks = [NotifyTaskAvailable]()
    
    // As a work-around to a limitation of always completing the newest daily check-in,
    // set this var before completing the SBATaskViewController to grab the schedule at this date
    var scheduleDateForMostRecentQuickCheckIn: Date?
    
    override init(delegate: SBAScheduledActivityManagerDelegate?) {
        super.init(delegate: delegate)
        
        // Set days behind and days ahead to only cache today's activities.
        self.daysBehind = 0
        self.daysAhead = 15
        
        // Add an observer to reload the data whenever the app returns to the foreground.
        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIApplicationWillEnterForeground, object: nil, queue: OperationQueue.main) { [weak self] (_) in
            self?.reloadData()
        }
    }
    
    func completedCount(for taskGroup: TaskGroup) -> Int {
        return scheduleSections.filter({ $0.items.find({ $0.taskGroup == taskGroup })?.isCompleted ?? false }).count
    }
    
    func isTodayCompleted(for taskGroup: TaskGroup) -> Bool {
        guard let todaySection = self.scheduleSections.first(where: { Calendar.gregorian.isDateInToday($0.date) }),
            let todayItem = todaySection.items.first(where: { $0.taskGroup == taskGroup })
        else {
            return false
        }
        return todayItem.isCompleted
    }
    
    override func resetData() {
        scheduleSections.removeAll()
        dayOne = nil
    }
    
    override func reloadData() {        
        forceReload()
    }
    
    func forceReload() {
    
        // Exit early if loading
        guard !self.isReloading else { return }
        
        // load schedules
        loadScheduledActivities(from: startStudy, to: scheduleAhead)
    }
    
    override func load(scheduledActivities: [SBBScheduledActivity]) {

        // Update the schedules if this is a cache, there are no schedules or this is the full range
        if self.scheduleSections.count == 0 || self.loadingState == .fromServerForFullDateRange {
            let (sections, startDate) = ScheduleSection.buildSchedule(with: scheduledActivities, enrollmentDate: enrollment, studyDuration: studyDuration)
            self.dayOne = startDate
            updateSchedules(newSections: sections,
                            shouldResetNotifications: self.loadingState == .fromServerForFullDateRange)
        }
        
        // call super with the full set
        super.load(scheduledActivities: scheduledActivities)
        
        // If we were waiting for a task to become available, see if it is now
        for notifyTask in self.notifyAvailableTasks {
            if self.isNotifyTaskAvailable(taskId: notifyTask.taskId) {
                notifyTask.callback(notifyTask.taskId)
            }
        }
        self.notifyAvailableTasks = self.notifyAvailableTasks.filter({ (notifyTask) -> Bool in
            return self.isNotifyTaskAvailable(taskId: notifyTask.taskId)
        })
    }
    
    func updateSchedules(newSections: [ScheduleSection], shouldResetNotifications: Bool) {
        DispatchQueue.main.async {
            
            // Set the new values
            self.scheduleSections = newSections
            
            // refresh the delegate
            self.delegate?.reloadFinished(self)
            
            // update the reminders
            if shouldResetNotifications {
                self.updateReminderNotifications()
            }
        }
    }
    
    func scheduleItemsToRemindOf() -> [ScheduleItem] {
        let unfinishedCardioSections = self.scheduleSections.filter({
            ($0.items[0].taskGroup.identifier as NSString).hasPrefix("Cardio") &&
            !$0.items[0].isCompleted
        })
        guard unfinishedCardioSections.count > 0 else { return [] }
        
        var items: [ScheduleItem] = []
        for section in unfinishedCardioSections {
            items.append(contentsOf: section.items)
        }
        
        return items
    }
    
    func updateReminderNotifications() {
        
        // use dispatch async to allow the method to return and put updating reminders on the next run loop
        DispatchQueue.main.async {
            
            // Get previous reminders so we can remove ours
            UNUserNotificationCenter.current().getPendingNotificationRequests(completionHandler: { (reminders) in
                // Get identifiers of previous Schedule-based reminders
                let myReminders = reminders.mapAndFilter({ (reminder) -> String? in
                    if (reminder.content.categoryIdentifier == "org.sagebase.crfModuleApp.Schedule") {
                        return reminder.identifier
                    }
                    else { return nil }
                })
                
                // Remove them
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: myReminders)
                
                // Check that there are any reminders to set and otherwise, do not even check for permission
                let remindItems = self.scheduleItemsToRemindOf()
                guard remindItems.count > 0 else { return }
                
                // Check for permission and if granted, then schedule the reminders
                UNUserNotificationCenter.current().getNotificationCategories() { [weak self] (categories) in
                    if categories.count > 0 {
                        self?.addLocalNotifications()
                    }
                    else {
                        self?.requestAuthorizationForNotifications()
                    }
                }
            })
        }
    }
    
    fileprivate func requestAuthorizationForNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .alert, .sound]) { [weak self] (granted, _) in
            if granted {
                self?.addLocalNotifications()
            }
        }
    }
    
    fileprivate func addLocalNotifications() {
        DispatchQueue.main.async {
            for item in self.scheduleItemsToRemindOf() {
                item.scheduleReminder()
            }
        }
    }

    func createTaskViewController(for taskIdentifier: TaskIdentifier) -> UIViewController? {
        
        let scheduleFilter = SBBScheduledActivity.availableTodayPredicate()
        guard let schedule = self.activities.reversed().find({
            $0.activityIdentifier == taskIdentifier.rawValue &&
                scheduleFilter.evaluate(with: $0)
        }) else { return nil }
        
        return self.createAppropriateTaskViewController(for: schedule)
    }
    
    override func update(schedule: SBBScheduledActivity, task: ORKTask, result: ORKTaskResult, finishedOn: Date?) {
        super.update(schedule: schedule, task: task, result: result, finishedOn: finishedOn)
        
        // Since this is a singleton, it's better to post a notification for events
        // rather than play king of the hill with the delegate
        // This notification will let view controllers know they should update the UI
        // because a scheduled task has been updated
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: self.scheduleUpdatedNotificationName, object: nil)
        }
    }
    
    override func sendUpdated(scheduledActivities: [SBBScheduledActivity]) {
        
        if let schedule = scheduledActivities.first,
            let section = self.scheduleSections.first(where: { $0.date.isToday }),
            let item = section.items.first,
            let dayOne = self.dayOne,
            let idx = self.activities.index(where: { $0.guid == schedule.guid }) {
            
            // Replace the activity
            var activities = self.activities
            activities.remove(at: idx)
            activities.insert(schedule, at: idx)
            self.activities = activities
        
            // Replace the section
            if let newItem = ScheduleItem(taskGroup: item.taskGroup, date: item.date, activities: activities, dayOne: dayOne, studyDuration: self.studyDuration),
                let sectionIdx = self.scheduleSections.index(where: { $0.date.isToday }) {
                let newSection = ScheduleSection(items: [newItem])
                var sections = self.scheduleSections
                sections.remove(at: sectionIdx)
                sections.insert(newSection, at: sectionIdx)
                self.scheduleSections = sections
            }
            
            self.delegate?.reloadFinished(self)
        }
        
        super.sendUpdated(scheduledActivities: scheduledActivities)
    }
    
    /**
     If the task is available right away, the callback will be invoked
     Otherwise, we will save the callback to be executed later when today's task is available
     */
    public func notifyWhenTaskIsAvailable(taskId: String, callback: @escaping (String) -> Void) {
        if self.isNotifyTaskAvailable(taskId: taskId) {
            callback(taskId)
        } else {
            let notifyLater = NotifyTaskAvailable(taskId: taskId, callback: callback)
            self.notifyAvailableTasks.append(notifyLater)
        }
    }
    
    fileprivate func isNotifyTaskAvailable(taskId: String) -> Bool {
        let taskAvailablePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [SBBScheduledActivity.includeTasksPredicate(with: [taskId]),
                                                                                         SBBScheduledActivity.availableTodayPredicate()])
        return self.activities.contains { (schedule) -> Bool in
            return taskAvailablePredicate.evaluate(with: schedule)
        }
    }
    
    fileprivate class NotifyTaskAvailable {
        var taskId: String
        var callback: ((String) -> Void)
        
        init(taskId: String, callback: @escaping ((String) -> Void)) {
            self.taskId = taskId
            self.callback = callback
        }
    }
}
