# DevinoSDK 

## Requirements
- Xcode 11+
- Swift 5+
- iOS 11.0+

## Quick start guide

### Create APNs Certificate in [Apple Developer Account](https://developer.apple.com/account/)
- Creating an Explicit App ID in [Identifiers](https://developer.apple.com/account/resources/identifiers/list)
- Generating a new APNs certificate for your application in [Certificates](https://developer.apple.com/account/resources/certificates/list)
- Creating the Development and Distribution Provisioning Profile in [Profiles](https://developer.apple.com/account/resources/profiles/list)
- Creating the App Group ID in [Identifiers -> AppGroups](https://developer.apple.com/account/resources/identifiers/list/applicationGroup) (AppGroupID is required for your application and NotificationExtension to exchange important data through a common data container, remember this ID for further integration steps) 

### Adding DevinoSDK to your Xcode project
1.  Move **DevinoSDK.framework** to the Frameworks project folder:

<img src="https://i.gyazo.com/eb04f38bb7cbeeffce63d875499943a7.png" align="center" width="500" >

2. Set the necessary copy options to the project:

<img src="https://i.gyazo.com/8ce924fba99882ea15d024131f584643.png" align="center" width="500" >

3. After that, your project in Xcode should contain **DevinoSDK.framework**:

<img src="https://i.gyazo.com/a66f1e1b1c08bb9bdac05628b17bdd39.png" align="center" width="200" >

4. Go to **Build Phases** and add **DevinoSDK.framework** to **Embed Frameworks**:

<img src="https://i.gyazo.com/7ef098c121361c098d0303b89022f0e4.png" align="center" width="700" >

### Adding  Devino Notification Service Extension to your Xcode project
1. Adding **Notification Service Extension** (File -> New -> Target -> Notification Service Extension):

<img src="https://i.gyazo.com/bccce8420c5ca2ed398594f1197d6766.png" align="center" width="500" >

<img src="https://i.gyazo.com/d11f17944baf62a8ddbb2df5c82f97a0.png" align="center" width="200" >

2. Correctly setup all targets iOS versions in project and Project Deployment Target, ***every targets must have the same versions***.

<img src="https://i.gyazo.com/ca39750deaa18445416388d5bce1f3cb.png" align="center" width="600" >

<img src="https://i.gyazo.com/66ce492984aaef0f8755483a85cc82ed.png" align="center" width="600" >

<img src="https://i.gyazo.com/ec194cf20c81d39daf2f591cb8c3e49d.png" align="center" width="600" >

3. Connection **DevinoNotificationService**:

```swift
import DevinoSDK
import UserNotifications

class NotificationService: DevinoNotificationService {
    
    override var appGroupsId: String? {
        return "group.com.fruktorum.DevinoPush"
    }
    
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        super.didReceive(request, withContentHandler: contentHandler)
        // Your code
    }
}
```
4. Add AppGroups in Signing & Capabilities for project targets and NotificationService
5. While debugging the NotificationService, make sure you have started the project correctly. You should build and run the NotificationService extension schema. 

**Notification Service Extension** needed to modify the contents of notifications (for example, to display pictures in notifications).

### Configuring DevinoSDK in AppDelegate:

**1. Adding ***import DevinoSDK***:**
```swift
import DevinoSDK
```
**2. Initialize ***DevinoUNUserNotificationCenter***:**
```swift
let devinoUNUserNotificationCenter = DevinoUNUserNotificationCenter()
```

**3. Setting the AppGroupID previously created in Apple Developer Account (appGroupId):**
```swift
let appGroupId = "group.com.fruktorum.DevinoPush" //example
```

**4. Making settings in the ***didFinishLaunchingWithOptions*** method:**

Add the Devino API key (key) and the PushApplication identifier (applicationId), which are issued after registering your application in your personal account.
Also, you can specify the interval for updating geolocation data in minutes (geoDataSendindInterval). The default is 0 minutes - never transfer data.
Also register the Apple Push Notification service.

Example didFinishLaunchingWithOptions:
```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
// set Devino configurations:
    let config = Devino.Configuration(key: "<key>", applicationId: <id>, appGroupId: <appGroupId>, geoDataSendindInterval: 1)
    Devino.shared.activate(with: config)
    Devino.shared.trackLaunchWithOptions(launchOptions)
// registration process with Apple Push Notification service:
    application.registerForRemoteNotifications()
    return true
 }
```
**5. In the ***didFinishLaunchingWithOptions*** method, assign the delegate object to the UNUserNotificationCenter object:**

```swift
// assign delegate object to the UNUserNotificationCenter object:
    UNUserNotificationCenter.current().delegate = devinoUNUserNotificationCenter
```

**6. Handlers of Action buttons in notifications:**

```swift
devinoUNUserNotificationCenter.setActionForUrl { url in
    // url action
}
devinoUNUserNotificationCenter.setActionForDefault {
    // default action
}
devinoUNUserNotificationCenter.setActionForDismiss {
    // dismiss action
}
devinoUNUserNotificationCenter.setActionForCustomDefault { action in
    // tap action on push
}
```

**7. Authentification with deviceToken:**

```swift
func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Devino.shared.registerForNotification(deviceToken)
}
```

**8. Tracking subscription status:**

```swift
func applicationWillEnterForeground(_ application: UIApplication) {
    Devino.shared.trackAppLaunch()
}
```

**9. Tracking application termination:**

```swift
func applicationWillTerminate(_ application: UIApplication) {
    Devino.shared.trackAppTerminated()
}
```

**10. Receive Remote Notifications:**
```swift
public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    Devino.shared.trackReceiveRemoteNotification(userInfo)
    completionHandler(.newData)
}
```

**11. Tracking Local Notifications:**
```swift
func application(_ application: UIApplication, handleActionWithIdentifier identifier: String?, for notification: UILocalNotification, completionHandler: @escaping () -> Void) {
    Devino.shared.trackLocalNotification(notification, with: identifier)
    completionHandler()
}
```

## Functionality DevinoSDK:

**1. Change user notification status:**

- Subscription: if confirmation of receipt of notifications is not required or it has been successful;
- Unsubscribe: if the user has disabled notifications in the application.

If the user has changed the notification settings in the system, the SDK monitors this event automatically.

**2. Sending user notification status:**

```swift
public func sendCurrentSubscriptionStatus(isSubscribe: Bool)
```

Example:
```swift
Devino.shared.sendCurrentSubscriptionStatus(isSubscribe: true)
```

**3. Receive user notification status:**

```swift
public func getLastSubscriptionStatus(_ completionHandler: @escaping (Bool) -> Void)
```

Example:
```swift
Devino.shared.getLastSubscriptionStatus { result in
    //do smth with result
}
```

**4. Update user data:**

```swift
public func setUserData(phone: String?, email: String?)
```

It is used in two cases:
- The user logged in to the application (automatically);
- The user has changed his personal data.

Example:
```swift
Devino.shared.setUserData(phone: "+79123456789", email: "test@gmail.com")
```
Phone format - +79XXXXXXXXX, email format - XXXX@XX.XX 

To update user data, all fields are required.

**5. Set a custom URL on the registartion screen:**
```swift
final public func setupApiRootUrl(with apiRootUrl: String)
```

Example:
```swift
Devino.shared.setupApiRootUrl(with: "https://integrationapi.net")
```

**5. Send geolocation:**

In the Info.plist file sets the permissions Privacy - Location Always and When In Use Usage Description and Privacy - Location When In Use Usage Description to read the geolocation.

Definition method of tracking location:
```swift
public func trackLocation()
```
Geolocation tracking is called once every N minutes. Minutes are specified using the **geoDataSendindInterval** property in the settings.
Example:
```swift
Devino.shared.trackLocation()
```
A notification with coordinates comes after determining the geolocation. Notification example:

<img src="https://i.gyazo.com/463b4cd74c2292ddb7e3ead3cdfad2e9.png" align="center" width="300" >

## Send custom Push Notifications:

**Push notification options:**

| Parameter | Type | Description | Example | Required field |
| ------ | ------ | ------ | ------ | ------ |
| title | `String` | Push message header (up to 50 characters) | `"Title"` | No |
| text | `String` | Text Push Messages (up to 150 characters) | `"text"` | No |
| badge | `Badge` | .zero (0) - if you need to remove the badge icon, .one (1) | `.zero` | No |
| validity | `Int` | Push message lifetime, maximum is 2419200 (in seconds) | `2419200` | No |
| priority | `Priority` | Message sending priority | `.realtime` | No |
| silentPush | `Bool` | A flag that tells the recipient that it does not need to be displayed to the client when receiving a notification | `false` | No |
| options | `[String: Any]` | Additional parameters to be transferred to the device | `["key": "value"]` | No |
| sound | `String` | The name of the sound file from the application. If no sound file is found, or if a default value is specified (“default”), the system plays a default warning sound. | `"push_sound.wav"` | No |
| buttons | `[ActionButton]` | Active buttons notification. A maximum of 3 objects can be added. | `[ActionButton(caption: "Title", action: "https://...")]` | No |
| linkToMedia | `String` | Additional attachments notifications (pictures, sounds, videos) | `"https://..."` | No |
| action | `String` | The action that should occur when a notification is clicked | `"https://..."` | No |

**`Badge` definition:**
```swift
public enum Badge: Int {
    case zero = 0
    case one = 1
}
```
**`Priority` definition:**
```swift
public enum Priority: String {
    case mediul = "MEDIUM"
    case low = "LOW"
    case high = "HIGH"
    case realtime = "REALTIME"
}
```
**`ActionButton` definition:**
```swift
public class ActionButton {
    var caption: String //name button
    var action: String //urls/deep link
} 
```
**Method definition:**
```swift
public func sendPushNotification(title: String? = "Devino Telecom", text: String? = "Text notification", badge: DevinoSDK.Badge? = nil, validity: Int? = 2419200, priority: DevinoSDK.Priority = .realtime, silentPush: Bool? = nil, options: [String : Any]? = nil, sound: String? = "default", buttons: [DevinoSDK.ActionButton]? = nil, linkToMedia: String? = nil, action: String? = nil)
```
**Example:**
```swift
Devino.shared.sendPushNotification(sound: "push_sound.wav", linkToMedia: https://i.gyazo.com/3dd58384ebf8c8b9bf39e7f445c8fb16.png)
```
<img src="https://i.gyazo.com/5cb496308971a70280987195233a2acf.png" align="center" width="300" >
<img src="https://i.gyazo.com/e446575aa51158795d00be2190dab218.png" align="center" width="300" >
<img src="https://i.gyazo.com/4ae793ac4086b3978d6f74b72716b9f5.png" align="center" width="300" >


## Logs from SDK:

**Property definition:**
```swift
public var logger: ((String) -> Void)?
```
**Example:**
```swift
Devino.shared.logger = { logStr in
   //do something 
}
```
