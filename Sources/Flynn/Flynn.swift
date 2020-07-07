//
//  Actor.swift
//  Flynn
//
//  Created by Rocco Bowling on 5/10/20.
//  Copyright © 2020 Rocco Bowling. All rights reserved.
//

import Foundation

open class Flynn {
#if DEBUG
    public static var checkForUnsafeArguments: Bool = true
#else
    public static var checkForUnsafeArguments: Bool = false
#endif

    private static var schedulers: [Scheduler] = []
    private static var schedulerIdx: Int = 0
    private static var running = AtomicContidion()
    private static var device = Device()

    public class func startup() {
        running.checkInactive {
            for idx in 0..<device.eCores {
                schedulers.append(Scheduler(idx, .onlyEfficiency))
            }
            for idx in 0..<device.pCores {
                schedulers.append(Scheduler(idx, .onlyPerformance))
            }
        }
    }

    public class func shutdown() {
        running.checkActive {
            for scheduler in schedulers {
                scheduler.join()
            }
            schedulers.removeAll()
        }
    }

    public static var cores: Int {
        return device.cores
    }

    @inline(__always)
    private static func minimumSchedulerWithStride(_ stride: StrideTo<Int>) -> Scheduler {
        var minIdx = 0
        var minCount = 999999

        for idx in stride {
            let count = schedulers[idx].count
            if count == 0 {
                return schedulers[idx]
            }
            if minIdx == -1 || count < minCount {
                minCount = count
                minIdx = idx
            }
        }

        return schedulers[minIdx]
    }

    public static func schedule(_ actor: Actor, _ coreAffinity: CoreAffinity) {
        if coreAffinity == .onlyEfficiency {
            minimumSchedulerWithStride( stride(from: 0, to: device.eCores, by: 1) ).schedule(actor)
        } else if coreAffinity == .onlyPerformance {
            minimumSchedulerWithStride( stride(from: device.eCores, to: device.cores, by: 1) ).schedule(actor)
        } else if coreAffinity == .preferPerformance {
            minimumSchedulerWithStride( stride(from: device.cores-1, to: -1, by: -1) ).schedule(actor)
        } else {
            // preferEfficiency
            minimumSchedulerWithStride( stride(from: 0, to: device.cores, by: 1) ).schedule(actor)
        }
    }

    internal static func steal(_ scheduler: Scheduler) -> Bool {
        if schedulers.count != device.cores {
            return false
        }
        for victim in schedulers where victim.count > 1 && victim.index != scheduler.index {
            if let actor = victim.steal() {
                scheduler.schedule(actor)
                return true
            }
        }
        return false
    }
}
