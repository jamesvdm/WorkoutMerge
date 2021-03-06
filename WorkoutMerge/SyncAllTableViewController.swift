//
//  SyncAllTableViewController.swift
//  WorkoutMerge
//
//  Created by Jason Kusnier on 9/12/15.
//  Copyright (c) 2015 Jason Kusnier. All rights reserved.
//

import UIKit
import HealthKit
import CoreData

class SyncAllTableViewController: UITableViewController {

    var workoutSyncAPI: WorkoutSyncAPI?
    
    let hkStore = HKHealthStore()
    typealias WorkoutRecord = (startDate: NSDate, durationLabel: String, workoutTypeLabel: String, checked: Bool, workoutDetails: WorkoutSyncAPI.WorkoutDetails?)
    typealias Workout = [WorkoutRecord]
    var workouts: Workout  = []
    
    let managedContext = (UIApplication.sharedApplication().delegate as! AppDelegate).managedObjectContext!
    
    var syncButton: UIBarButtonItem?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.syncButton = UIBarButtonItem(title: "Sync All", style: .Plain, target: self, action: "syncItems")
        self.syncButton?.possibleTitles = ["Sync All", "Sync Selected"];
        navigationItem.rightBarButtonItem = self.syncButton
        
        if !HKHealthStore.isHealthDataAvailable() {
            print("HealthKit Not Available")
//            self.healthKitAvailable = false
//            self.refreshControl.removeFromSuperview()
        } else {
            let readTypes = Set(arrayLiteral:
                HKObjectType.workoutType(),
                HKObjectType.quantityTypeForIdentifier(HKQuantityTypeIdentifierHeartRate)!
            )
            
            hkStore.requestAuthorizationToShareTypes(nil, readTypes: readTypes, completion: { (success: Bool, err: NSError?) -> () in
                
                let actInd : UIActivityIndicatorView = UIActivityIndicatorView(frame: CGRectMake(0,0, 50, 50)) as UIActivityIndicatorView
                actInd.center = self.view.center
                actInd.hidesWhenStopped = true
                actInd.activityIndicatorViewStyle = UIActivityIndicatorViewStyle.Gray
                self.view.addSubview(actInd)
                actInd.startAnimating()
                
                if success {
                    self.readWorkOuts({(results: [AnyObject]!, error: NSError!) -> () in
                        if let results = results as? [HKWorkout] {
                            dispatch_async(dispatch_get_main_queue()) {
                                self.workouts = []
                                var queue = results.count
                                for workout in results {
                                    queue--
                                    
                                    if let _ = self.managedObject(workout) {
                                        // Verify the workout hasn't already been synced
                                        
                                        // If the last item was already synced, we will stop the progress
                                        // FIXME this should be done with a timer
                                        if queue == 0 {
                                            // TODO Check the timer status, cancel if needed
                                            dispatch_async(dispatch_get_main_queue()) {
                                                self.tableView.reloadData()
                                                actInd.stopAnimating()
                                            }
                                        }
                                    } else {
                                        let totalDistance: Double? = (workout.totalDistance != nil) ? workout.totalDistance!.doubleValueForUnit(HKUnit.meterUnit()) : nil
                                        let totalEnergyBurned: Double? = workout.totalEnergyBurned != nil ? workout.totalEnergyBurned!.doubleValueForUnit(HKUnit.kilocalorieUnit()) : nil
                                        let activityType = self.workoutSyncAPI?.activityType(workout.workoutActivityType)
                                        
                                        var workoutRecord = (workout.UUID, type: activityType, startTime: workout.startDate, totalDistance: totalDistance, duration: workout.duration, averageHeartRate: nil, totalCalories: totalEnergyBurned, notes: nil, otherType: nil, activityName: nil) as WorkoutSyncAPI.WorkoutDetails
                                        
                                        let queue = queue
                                        self.averageHeartRateForWorkout(workout, success: { d in
                                            if let d = d {
                                                workoutRecord.averageHeartRate = Int(d)
                                            }
                                            self.workouts.append((startDate: workout.startDate, durationLabel: self.stringFromTimeInterval(workout.duration), workoutTypeLabel: HKWorkoutActivityType.hkDescription(workout.workoutActivityType), checked: false, workoutDetails: workoutRecord) as WorkoutRecord)
                                       
                                            if queue == 0 {
                                                // TODO Check timer, cancel and reset
                                                dispatch_async(dispatch_get_main_queue()) {
                                                    self.tableView.reloadData()
                                                    actInd.stopAnimating()
                                                }
                                            }
                                        }, tryAgain: true)
                                    }
                                }
                            }
                        }
                    })
                } else {
                    actInd.stopAnimating()
                }
            })
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    // MARK: - Table view data source

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.workouts.count
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCellWithIdentifier("syncAllCell") as? WorkoutTableViewCell {
            let workout  = self.workouts[indexPath.row]
            let startDate = workout.startDate.relativeDateFormat()
            
            if workout.checked {
                cell.accessoryType = .Checkmark
            } else {
                cell.accessoryType = .None
            }
            
            cell.startTimeLabel?.text = startDate
            cell.durationLabel?.text = workout.durationLabel
            cell.workoutTypeLabel?.text = workout.workoutTypeLabel
            
            return cell
        } else {
            return tableView.dequeueReusableCellWithIdentifier("syncAllCell")!
        }
    }

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        var workout  = self.workouts[indexPath.row]
        workout.checked = !workout.checked
        self.workouts[indexPath.row] = workout

        self.tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: UITableViewRowAnimation.Fade)
        self.tableView.deselectRowAtIndexPath(indexPath, animated: true)
        
        let anyTrue = self.workouts
            .map { return $0.checked }
            .reduce(false) { (sum, next) in return sum || next }
        
        if anyTrue {
            self.navigationItem.rightBarButtonItem?.title = "Sync Selected"
        } else {
            self.navigationItem.rightBarButtonItem?.title = "Sync All"
        }
    }

    func readWorkOuts(completion: (([AnyObject]!, NSError!) -> Void)!) {
        let sortDescriptor = NSSortDescriptor(key:HKSampleSortIdentifierStartDate, ascending: false)
        
        let sampleQuery = HKSampleQuery(sampleType: HKWorkoutType.workoutType(), predicate: nil, limit: 0, sortDescriptors: [sortDescriptor])
            { (sampleQuery, results, error ) -> Void in
                if let queryError = error {
                    print( "There was an error while reading the samples: \(queryError.localizedDescription)")
                }
                completion(results, error)
        }
        
        hkStore.executeQuery(sampleQuery)
    }
    
    func managedObject(workout: HKWorkout) -> NSManagedObject? {
        let uuid = workout.UUID.UUIDString
        let servicesPredicate: String
        if let _ = self.workoutSyncAPI as? RunKeeperAPI {
            servicesPredicate = "uuid = %@ AND syncToRunKeeper != nil"
        } else if let _ = self.workoutSyncAPI as? StravaAPI {
            servicesPredicate = "uuid = %@ AND syncToStrava != nil"
        } else {
            return nil
        }
        
        let fetchRequest = NSFetchRequest(entityName: "SyncLog")
        let predicate = NSPredicate(format: servicesPredicate, uuid)
        fetchRequest.predicate = predicate
        
        let fetchedEntities = try? self.managedContext.executeFetchRequest(fetchRequest)
        
        if let syncLog = fetchedEntities?.first as? NSManagedObject {
            return syncLog
        }
        
        return nil
    }
    
    func stringFromTimeInterval(interval:NSTimeInterval) -> String {
        
        let ti = NSInteger(interval)
        
        let seconds = ti % 60
        let minutes = (ti / 60) % 60
        let hours = (ti / 3600)
        
        return String(format: "%0.2d:%0.2d:%0.2d",hours,minutes,seconds)
    }
    
    func syncItems() {
        let workoutsToSync: Workout
        
        let anyTrue = self.workouts
            .map { return $0.checked }
            .reduce(false) { (sum, next) in return sum || next }
        
        if anyTrue {
            workoutsToSync = self.workouts.filter({$0.checked})
        } else {
            workoutsToSync = self.workouts
        }
        
        let vcu = ViewControllerUtils()
        
        vcu.showActivityIndicator(self.view)
        
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
        let managedContext = appDelegate.managedObjectContext!
        
        if let runKeeper = self.workoutSyncAPI as? RunKeeperAPI {
            // Loop over workoutsToSync
            workoutsToSync.forEach { workout in
                if let workoutDetail = workout.workoutDetails {
                    runKeeper.postActivity(workoutDetail, failure: { (error, msg) in
                        dispatch_async(dispatch_get_main_queue()) {
                            vcu.hideActivityIndicator(self.view)
                            let errorMessage: String
                            if let error = error {
                                errorMessage = "\(error.localizedDescription) - \(msg)"
                            } else {
                                errorMessage = "An error occurred while saving workout. Please verify that WorkoutMerge is still authorized through RunKeeper - \(msg)"
                            }
                            let alert = UIAlertController(title: "Error", message: errorMessage, preferredStyle: .Alert)
                            alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))
                            self.presentViewController(alert, animated: true, completion: nil)
                        }
                    },
                    success: { (savedKey) in
                        if let uuid = workout.workoutDetails?.UUID?.UUIDString {

                            if let syncLog = self.syncLog(uuid) {
                                syncLog.setValue(NSDate(), forKey: "syncToRunKeeper")
                                syncLog.setValue(savedKey, forKey: "savedKeyRunKeeper")
                                if let workoutType = workout.workoutDetails?.type {
                                    syncLog.setValue(workoutType, forKey: "workoutType")
                                }
                            } else {
                                let entity =  NSEntityDescription.entityForName("SyncLog", inManagedObjectContext: managedContext)
                                let syncLog = NSManagedObject(entity: entity!, insertIntoManagedObjectContext:managedContext)
                                syncLog.setValue(uuid, forKey: "uuid")
                                syncLog.setValue(NSDate(), forKey: "syncToRunKeeper")
                                syncLog.setValue(savedKey, forKey: "savedKeyRunKeeper")
                                if let workoutType = workout.workoutDetails?.type {
                                    syncLog.setValue(workoutType, forKey: "workoutType")
                                }
                            }

                            var error: NSError?
                            do {
                                try managedContext.save()
                            } catch let error1 as NSError {
                                error = error1
                                print("Could not save \(error)")
                            } catch {
                                fatalError()
                            }
                        }
                        
                        dispatch_async(dispatch_get_main_queue()) {
                            // TODO reload data in table - remove workouts synced
                            vcu.hideActivityIndicator(self.view)
                        }
                    })
                }
            }
        } else if let strava = self.workoutSyncAPI as? StravaAPI {
            // Loop over workoutsToSync
            workoutsToSync.forEach { workout in
//                strava
                
                if let workoutDetail = workout.workoutDetails {
                    strava.postActivity(workoutDetail, failure: { (error, msg) in
                    dispatch_async(dispatch_get_main_queue()) {
                        vcu.hideActivityIndicator(self.view)
                        let errorMessage: String
                        if let error = error {
                            errorMessage = "\(error.localizedDescription) - \(msg)"
                        } else {
                            errorMessage = "An error occurred while saving workout. Please verify that WorkoutMerge is still authorized through Strava - \(msg)"
                        }
                        let alert = UIAlertController(title: "Error", message: errorMessage, preferredStyle: .Alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))
                        self.presentViewController(alert, animated: true, completion: nil)
                    }

                    },
                    success: { (savedKey) in
                        if let uuid = workout.workoutDetails?.UUID?.UUIDString {

                            if let syncLog = self.syncLog(uuid) {
                                syncLog.setValue(NSDate(), forKey: "syncToRunKeeper")
                                syncLog.setValue(savedKey, forKey: "savedKeyRunKeeper")
                                if let workoutType = workout.workoutDetails?.type {
                                    syncLog.setValue(workoutType, forKey: "workoutType")
                                }
                            } else {
                                let entity =  NSEntityDescription.entityForName("SyncLog", inManagedObjectContext: managedContext)
                                let syncLog = NSManagedObject(entity: entity!, insertIntoManagedObjectContext:managedContext)
                                syncLog.setValue(uuid, forKey: "uuid")
                                syncLog.setValue(NSDate(), forKey: "syncToRunKeeper")
                                syncLog.setValue(savedKey, forKey: "savedKeyRunKeeper")
                                if let workoutType = workout.workoutDetails?.type {
                                    syncLog.setValue(workoutType, forKey: "workoutType")
                                }
                            }

                            var error: NSError?
                            do {
                                try managedContext.save()
                            } catch let error1 as NSError {
                                error = error1
                                print("Could not save \(error)")
                            } catch {
                                fatalError()
                            }
                        }
                        
                        dispatch_async(dispatch_get_main_queue()) {
                            // TODO reload data in table - remove workouts synced
                            vcu.hideActivityIndicator(self.view)
                        }
                    })
                }
            }
        }
    }
    
    func averageHeartRateForWorkout(workout: HKWorkout, success: (Double?) -> (), tryAgain: Bool) {

        let quantityType = HKObjectType.quantityTypeForIdentifier(HKQuantityTypeIdentifierHeartRate)
        let workoutPredicate = HKQuery.predicateForSamplesWithStartDate(workout.startDate, endDate: workout.endDate, options: .None)
        //            let startDateSort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        let query = HKStatisticsQuery(quantityType: quantityType!, quantitySamplePredicate: workoutPredicate, options: .DiscreteAverage) {
            (query, results, error) -> Void in
            
            if error != nil {
                print("\(error)")
                if tryAgain {
                    self.averageHeartRateForWorkout(workout, success: success, tryAgain: false)
                } else {
                    print("failed to retrieve heart rate data")
                    success(nil)
                }
            } else {
                if results!.averageQuantity() != nil {
                    let avgHeartRate = results!.averageQuantity()!.doubleValueForUnit(HKUnit(fromString: "count/min"));
                    
                    success(avgHeartRate)
                } else if tryAgain {
                    print("averageQuantity unexpectedly found nil")
                    self.averageHeartRateForWorkout(workout, success: success, tryAgain: false)
                } else {
                    print("failed to retrieve heart rate data")
                    success(nil)
                }
            }
        }
        
        hkStore.executeQuery(query)
    }
    
    func syncLog(uuid: String) -> NSManagedObject? {
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
        let managedContext = appDelegate.managedObjectContext!
        
        let fetchRequest = NSFetchRequest(entityName: "SyncLog")
        let predicate = NSPredicate(format: "uuid = %@", uuid)
        fetchRequest.predicate = predicate
        
        let fetchedEntities = try? managedContext.executeFetchRequest(fetchRequest)
        
        if let syncLog = fetchedEntities?.first as? NSManagedObject {
            return syncLog
        }
        
        return nil
    }
}
