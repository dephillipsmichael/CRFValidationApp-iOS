//
//  ResourceTests.swift
//  CRFModuleValidationTests
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

import XCTest
@testable import CRFModuleValidation
import BridgeAppSDK

class ResourceTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    
    func testHeartRateMeasurement() {
        
        let json = jsonForResource("HeartRate_Measurement")
        XCTAssertNotNil(json)
        
        let task = json?.createORKTask(with: SurveyFactory())
        XCTAssertNotNil(task)
        
        guard let _ = task as? SBANavigableOrderedTask else {
            XCTFail("\(String(describing: task)) nil or not expected type")
            return
        }
    }
    
    func test12MT() {
        
        let json = jsonForResource("Cardio_12MT")
        XCTAssertNotNil(json)
        
        let task = json?.createORKTask(with: SurveyFactory())
        XCTAssertNotNil(task)
        
        guard let orderedTask = task as? SBANavigableOrderedTask else {
            XCTFail("\(String(describing: task)) nil or not expected type")
            return
        }
        
        let steps = orderedTask.steps
        print(steps)
        
    }

    
    // MARK: Helper methods
    
    func jsonForResource(_ resourceName: String) -> NSDictionary? {
        
        let resourcePath = Bundle(for: self.classForCoder).path(forResource: resourceName, ofType:"json") ??
            Bundle.main.path(forResource: resourceName, ofType: "json")
        
        guard let path = resourcePath, let jsonData = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            XCTAssert(false, "Resource not found: \(resourceName)")
            return nil
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: jsonData, options: JSONSerialization.ReadingOptions(rawValue: 0)) as? NSDictionary else {
                XCTAssert(false, "Resource not an NSDictionary: \(resourceName)")
                return nil
            }
            return json
        }
        catch let err as NSError {
            XCTAssert(false, "Failed to parse json. \(err)")
        }
        
        return nil
    }
    
}