import EventKit
import Foundation

extension EKReminder {
    
    // MARK: - Private API Access
    
    /// Get the backing object that provides access to private APIs
    private var reminderBackingObject: AnyObject? {
        let backingObjectSelector = NSSelectorFromString("backingObject")
        let reminderSelector = NSSelectorFromString("_reminder")
        
        guard let unmanagedBackingObject = self.perform(backingObjectSelector),
              let unmanagedReminder = unmanagedBackingObject.takeUnretainedValue().perform(reminderSelector) else {
            return nil
        }
        
        return unmanagedReminder.takeUnretainedValue()
    }
    
    // NOTE: This is a workaround to access the URL saved in a reminder.
    // This property is not accessible through the conventional API.
    var attachedUrl: URL? {
        let attachmentsSelector = NSSelectorFromString("attachments")
        
        guard let backingObj = reminderBackingObject,
              let unmanagedAttachments = backingObj.perform(attachmentsSelector),
              let attachments = unmanagedAttachments.takeUnretainedValue() as? [AnyObject] else {
            return nil
        }
        
        for item in attachments {
            // NOTE: Attachments can be of type REMURLAttachment or REMImageAttachment.
            let attachmentType = type(of: item).description()
            guard attachmentType == "REMURLAttachment" else {
                continue
            }
            
            guard let unmanagedUrl = item.perform(NSSelectorFromString("url")),
                  let url = unmanagedUrl.takeUnretainedValue() as? URL else {
                continue
            }
            
            return url
        }
        
        return nil
    }
    
    // NOTE: This is a workaround to access the mail linked to a reminder.
    // This property is not accessible through the conventional API.
    var mailUrl: URL? {
        let userActivitySelector = NSSelectorFromString("userActivity")
        let storageSelector = NSSelectorFromString("storage")
        
        guard let backingObj = reminderBackingObject,
              let unmanagedUserActivity = backingObj.perform(userActivitySelector),
              let unmanagedUserActivityStorage = unmanagedUserActivity.takeUnretainedValue().perform(storageSelector),
              let userActivityStorageData = unmanagedUserActivityStorage.takeUnretainedValue() as? Data else {
            return nil
        }
        
        // NOTE: UserActivity type is UniversalLink, so in theory it could be targeting apps other than Mail.
        // If it starts with "message:" then it is related to Mail.
        guard let userActivityStorageString = String(bytes: userActivityStorageData, encoding: .utf8),
              userActivityStorageString.starts(with: "message:") else {
            return nil
        }
        
        return URL(string: userActivityStorageString)
    }
    
    // NOTE: This is a workaround to access the parent reminder id of a reminder.
    // This property is not accessible through the conventional API.
    var parentId: String? {
        let parentReminderSelector = NSSelectorFromString("parentReminderID")
        let uuidSelector = NSSelectorFromString("uuid")
        
        guard let backingObj = reminderBackingObject,
              let unmanagedParentReminder = backingObj.perform(parentReminderSelector),
              let unmanagedParentReminderId = unmanagedParentReminder.takeUnretainedValue().perform(uuidSelector),
              let parentReminderId = unmanagedParentReminderId.takeUnretainedValue() as? UUID else {
            return nil
        }
        
        return parentReminderId.uuidString
    }
    
    // MARK: - Convenience Properties
    
    /// Returns true if this reminder has a parent (i.e., it's a subtask)
    var isSubtask: Bool {
        return parentId != nil
    }
    
    /// Returns all attachments (URLs and potentially other types)
    var allAttachments: [AnyObject] {
        let attachmentsSelector = NSSelectorFromString("attachments")
        
        guard let backingObj = reminderBackingObject,
              let unmanagedAttachments = backingObj.perform(attachmentsSelector),
              let attachments = unmanagedAttachments.takeUnretainedValue() as? [AnyObject] else {
            return []
        }
        
        return attachments
    }
} 