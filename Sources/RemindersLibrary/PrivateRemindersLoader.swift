import Foundation
import Darwin

#if PRIVATE_REMINDERS_ENABLED

/// Loads private Reminders frameworks at runtime
public class PrivateRemindersLoader {
    private static var isLoaded = false
    
    public static func loadPrivateFrameworks() {
        guard !isLoaded else { return }
        
        let remindersUICorePath = "/System/Library/PrivateFrameworks/RemindersUICore.framework/RemindersUICore"
        let reminderKitPath = "/System/Library/PrivateFrameworks/ReminderKit.framework/ReminderKit"
        
        // Try to load the frameworks
        if dlopen(remindersUICorePath, RTLD_NOW) != nil &&
           dlopen(reminderKitPath, RTLD_NOW) != nil {
            isLoaded = true
            print("Private Reminders frameworks loaded successfully")
        } else {
            print("Warning: Could not load private Reminders frameworks")
            print("Private API features will be disabled")
        }
    }
    
    public static var isPrivateAPIAvailable: Bool {
        return isLoaded
    }
}

#else

/// Stub implementation when private APIs are disabled
public class PrivateRemindersLoader {
    public static func loadPrivateFrameworks() {
        // No-op when private APIs are disabled
    }
    
    public static var isPrivateAPIAvailable: Bool {
        return false
    }
}

#endif