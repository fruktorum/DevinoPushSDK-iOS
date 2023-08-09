//
//  DevinoSDK.swift
//  DevinoSDK
//
//  Created by alexej_ne on 27.07.2018.
//  Copyright © 2018 Devino. All rights reserved.
//

import UIKit
import UserNotifications
import CoreLocation

public final class Devino: NSObject {
    
//MARK: -Configurations:
    
    private static let deviceTokenFlag = "DevinoDeviceTokenFlag"
    private static let isSubscribedFlag = "DevinoIsSubscribedFlag"
    private static let configKeyFlag = "configKeyFlag"
    private static let apiRootUrl = "apiRootUrl"
    private static let appGroupId = "appGroupId"
    private static let appId = "appId"
 
    public struct Configuration {
        // Апи ключ Devino (X-Api-Key)
        public let key: String
        // id PushApplication который выдаётся клиенту после регистрации приложения в ЛК
        public let applicationId: Int
        // App Group identifier from Apple Developer Account
        public let appGroupId: String
        // Интервал в минутах для обновления данных геолокации
        public let geoDataSendindInterval: Int
        // Сервер
        public let apiRootUrl:String
        // Порт
        public let apiRootPort: Int?
        
        public init(key: String, applicationId: Int, appGroupId: String, geoDataSendindInterval: Int = 0, apiRootUrl: String = "integrationapi.net", apiRootPort: Int? = 6602) {
            self.key = key
            self.applicationId = applicationId
            self.appGroupId = appGroupId
            self.geoDataSendindInterval = geoDataSendindInterval
            self.apiRootUrl = apiRootUrl
            self.apiRootPort = apiRootPort
        }
    }
    
    public var debug: Bool = false
    public var logger: ((String) -> Void)? = nil
    private var isSendPush = false
    
    func log(_ str: String) {
        logger?("\n\n\(Date.getLogTime()): \n\(str)")
    }
    public static var shared = Devino()
    
    private static var pushToken: String? {
        guard let userDefaults = UserDefaultsManager.userDefaults else {
            return nil
        }
        return userDefaults.string(forKey: Devino.deviceTokenFlag)
    }
    
    private var configuration: Configuration? = nil
    private var email: String? = nil
    private var phone: String? = nil
    private lazy var locManager: CLLocationManager = {
        let locationManager = CLLocationManager()
        locationManager.delegate = self
        return locationManager
    }()
    private var timer: Timer? = nil
    public static var isUserNotificationsAvailable: Bool {
        guard let userDefaults = UserDefaultsManager.userDefaults else {
            return false
        }
        return userDefaults.bool(forKey: Devino.isSubscribedFlag)
    }
    
//MARK: -Public:
    
    public func activate(with config: Configuration) {
        configuration = config
        UserDefaultsManager.userDefaults = UserDefaults(suiteName: config.appGroupId)
        if let userDefaults = UserDefaultsManager.userDefaults {
            userDefaults.set(config.key, forKey: Devino.configKeyFlag)
            userDefaults.set(config.apiRootUrl, forKey: Devino.apiRootUrl)
            userDefaults.set(config.appGroupId, forKey: Devino.appGroupId)
            userDefaults.set(config.applicationId, forKey: Devino.appId)
            userDefaults.synchronize()
        }
        log("Devino activate. Configurations received!")
    }
    
    public func trackAppLaunch() {
        
        guard let userDefaults = UserDefaultsManager.userDefaults else { return }
        
        log("TrackAppLaunch")
        log("Push token: \(String(describing: Devino.pushToken))")
        
        if Devino.pushToken != nil {
            getPermissionForPushNotifications { subscribed in
                self.log("Subscribed if Devino.pushToken != nil: \(subscribed)")
                self.makeRequest(.usersAppStart)
            }
        } else {
            if let token = userDefaults.string(forKey: Devino.deviceTokenFlag) {
                log("Push token from UserDefaults: \(token)")
            }
        }
        log("Is the remote registration process completed successfully: \(UIApplication.shared.isRegisteredForRemoteNotifications)")
        if let existedIsSubscribedFlag = userDefaults.value(forKey:
            Devino.isSubscribedFlag) as? Bool, existedIsSubscribedFlag != UIApplication.shared.isRegisteredForRemoteNotifications {
            log("Devino.isUserNotificationsAvailable: \(Devino.isUserNotificationsAvailable))")
            makeRequest(.usersSubscribtion(subscribed: Devino.isUserNotificationsAvailable))
        } else {
            getPermissionForPushNotifications { subscribed in
                self.log("Subscribed if Devino.pushToken == nil: \(subscribed)")
                self.makeRequest(.usersAppStart)
            }
        }
    }
    
    public func trackLaunchWithOptions(_ options: [UIApplication.LaunchOptionsKey: Any]?) {
        log("TrackLaunchWithOptions")
        UIApplication.shared.applicationIconBadgeNumber = 0
        trackAppLaunch()
        if let time = configuration?.geoDataSendindInterval, time > 0, CLLocationManager.locationServicesEnabled() {
            trackLocation()
        }
        guard let notification = options?[UIApplication.LaunchOptionsKey.remoteNotification] as? [AnyHashable: Any], let _ = getPushId(notification) else  { return }
    }
    
    public func trackReceiveRemoteNotification(_ userInfo: [AnyHashable: Any], appGroupsId: String) {
        UserDefaultsManager.userDefaults = UserDefaults(suiteName: appGroupsId)
        
        guard let pushId = getPushId(userInfo) else {
            log("Push Id not found in aps")
            return
        }
        guard let pushToken = Devino.pushToken else {
            log("Push Token not found")
            return
        }
        log("Push Id = \(pushId), Push Token = \(pushToken)")
        makeRequest(.pushEvent(pushToken: pushToken, pushId: pushId, actionType: .delivered, actionId: getNotificationActionId(userInfo)))
        log("Push DELIVERED: \(userInfo)")
        
        if Devino.isUserNotificationsAvailable {
            updateActionButtons(userInfo)
        } else {
            log("Error: isUserNotificationsAvailable FALSE!")
        }
    }
    
    public func trackNotificationResponse(_ response: UNNotificationResponse, _ actionId: String? = nil) {
        let userInfo = response.notification.request.content.userInfo
        guard let pushToken = Devino.pushToken, let pushId = getPushId(userInfo) else { return }
        log("Push OPENED by Identifier \(response.actionIdentifier): \n\(userInfo)\n")
        makeRequest(.pushEvent(pushToken: pushToken, pushId: pushId, actionType: .opened, actionId: actionId != nil ? actionId : getNotificationActionId(userInfo)))
    }
    
    public func trackAppTerminated() {
        makeRequest(.usersEvent(eventName: "device-terminated", eventData: [:]))
    }
    
    public func sendCurrentSubscriptionStatus(isSubscribe: Bool) {
        log("SendCurrentSubscriptionStatus: \(isSubscribe)")
        makeRequest(.usersSubscribtion(subscribed: isSubscribe))
    }
    
    public func getLastSubscriptionStatus(_ completionHandler: @escaping (Result<Bool, Error>) -> Void) {
        log("GetLastSubscriptionStatus")
        makeRequest(.usersSubscriptionStatus) { [weak self] (data, response, error) in
            guard let self = `self` else { return }
            self.fetchSubscriptionStatus(data, response, error) { result in
                switch result {
                case .success(let result):
                    completionHandler(.success(result))
                case .failure(let error):
                    completionHandler(.failure(error))
                }
            }
        }
    }
    
    private func fetchSubscriptionStatus(_ data: Data?, _ response: HTTPURLResponse?, _ error: Error?, _ completionHandler: @escaping (Result<Bool, Error>) -> Void) {
        log("FetchSubscriptionStatus")
        if let error = error {
            self.log("Error = \(error)")
            completionHandler(.failure(error))
        }
        if let data = data {
            do {
                let jsonData = try JSONSerialization.jsonObject(with: data, options: []) as? [String: AnyObject]
                if let result = jsonData?["result"] as? Bool {
                    self.log("Result last subscription = \(result)")
                    self.log("Result current subscription = \(Devino.isUserNotificationsAvailable)")
                    completionHandler(.success(result))
                } else {
                    self.log("Error = \(String(describing: jsonData))")
                    completionHandler(.failure(ErrorHandler.failureJSONData))
                }
            } catch {
                self.log("Could not parse data: \(error)")
                completionHandler(.failure(error))
            }
        } else {
            completionHandler(.failure(ErrorHandler.failureServerData))
        }
    }
    
    //MARK: User Data:
    public func setUserData(phone: String?, email: String?) {
        self.email = email
        self.phone = phone
        makeRequest(.usersData(email: email, phone: phone, custom: [:]))
    }
    
    //MARK: Geo Data:
    public func sendPushWithLocation() {
        log("SendPushWithLocation")
        isSendPush = true
        locManager.desiredAccuracy = kCLLocationAccuracyBest
        locManager.requestAlwaysAuthorization()
        Devino.shared.startUpdateLocation()
    }
    
    
    //MARK: Event Data:
    public func trackEvent(name: String, params: [String: Any] = [:]) {
        log("CUSTOM EVENT: Name: \"\(name)\" \n Parameters: \(params)")
        makeRequest(.usersEvent(eventName: name, eventData: params))
    }
    
    //MARK: Notifications:
    public func sendPushNotification(title: String? = "Devino Telecom",
                                   text: String? = "Text notification",
                                   badge: Badge? = nil,
                                   validity: Int? = nil,
                                   priority: Priority = .realtime, //MEDIUM, LOW, MEDIUM, HIGH, REALTIME
                                   silentPush: Bool? = nil,
                                   options: [String: Any]? = nil,
                                   sound: String? = "default",
                                   buttons: [ActionButton]? = nil,
                                   linkToMedia: String? = nil,
                                   action: String? = nil) {
        log("SendPushNotification")
        log("GetPermissionForPushNotifications")
        getPermissionForPushNotifications { subscribed in
            if subscribed {
                self.log("PUSH sendPushWithOption: \(subscribed)")
                let apns = self.createAPNsOptions(sound, linkToMedia, buttons, action)
                self.makeRequest(.messages(title: title, text: text, badge: badge?.rawValue, validity: validity, priority: priority, silentPush: silentPush, options: options, apns: apns))
            } else {
                self.log("PUSH sendPushWithOption: \(subscribed)")
                self.showPushPermissionMsg()
            }
        }
    }
    
    public func registerForNotification(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        log("New DeviceToken: \(token)")
        guard let userDefaults = UserDefaultsManager.userDefaults else {
            log("Error: UserDefaults in registerForNotification not found!")
            return
        }
        let existedToken = userDefaults.string(forKey: Devino.deviceTokenFlag)
        log("ExistedToken: \(String(describing: existedToken))")
        userDefaults.set(token, forKey: Devino.deviceTokenFlag)
        userDefaults.synchronize()
        log("DeviceToken updated in UserDefaults")
        if existedToken == nil {
            log("ExistedToken = nil, need to update UserData")
            makeRequest(.usersData(email: email, phone: phone, custom: [:]))
        }
    }
    
    public func getOptions(_ userInfo: [AnyHashable: Any]) -> [String: Any]? {
        guard let val = userInfo["aps"],
            let dic = val as? [AnyHashable: Any] else { return nil }
        if let options = dic["settings"] as? [String: Any] {
            return options
        }
        return nil
    }
    
    // MARK: Change apiRoot URL
    public func setupApiRootUrl(with apiRootUrl: String) {
        if let userDefaults = UserDefaultsManager.userDefaults {
            userDefaults.removeObject(forKey: Devino.apiRootUrl)
            userDefaults.set(apiRootUrl, forKey: Devino.apiRootUrl)
            log("Api Root URL is changed")
        } else {
            log("Error: UserDefaults not found")
        }
    }
    
//MARK: -Private:
    
    //MARK: Geo Data:
    private func trackLocation() {
        log("Track location")
        guard let time = configuration?.geoDataSendindInterval, time > 0 else { return }
        locManager.desiredAccuracy = kCLLocationAccuracyBest
        locManager.requestAlwaysAuthorization()
        Devino.shared.startUpdateLocation()
        timer = Timer.scheduledTimer(timeInterval: TimeInterval(time * 60), target: self, selector: (#selector(Devino.shared.startUpdateLocation)), userInfo: nil, repeats: true)
    }
    
    private func updateActionButtons(_ userInfo: [AnyHashable: Any]) {
        if let userInfo = userInfo as? [String: AnyObject] {
            var category = "content-buttons"
            if let val = userInfo["aps"],
                let dic = val as? [AnyHashable: Any],
                let categoryFromPush = dic["category"] as? String{
                category = categoryFromPush
            }
            var actionButtons: [AnyObject] = []
            if let buttons = userInfo["buttons"] as? [AnyObject], buttons.count > 0 {
                actionButtons.append(contentsOf: Array(buttons.prefix(3)))
            }
            registerNotificationCategories(actionButtons: actionButtons, category: category)
        }
    }
    
    private func registerNotificationCategories(actionButtons: [AnyObject], category: String) {
        var notificationActions = [UNNotificationAction]()
        for button in actionButtons {
            if let button = button as? [String: String] {
                if let title = button["caption"], let action = button["action"] {
                    let action = UNNotificationAction(identifier: action, title: title, options: UNNotificationActionOptions.foreground)
                    notificationActions.append(action)
                }
            }
        }
        let contentAddedCategory = UNNotificationCategory(identifier: category, actions: notificationActions, intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "", options: .customDismissAction)
        UNUserNotificationCenter.current().setNotificationCategories([contentAddedCategory])
    }
    
    
    private func createAPNsOptions(_ sound: String?, _ linkToMedia: String?, _ buttons: [ActionButton]?, _ action: String?) -> [String: Any]? {
        var apnsOptions = [String: Any]()
        apnsOptions["sound"] = (sound != nil && sound != "") ? sound : "Default"
        if let linkToMedia = linkToMedia {
            apnsOptions["linkToMedia"] = linkToMedia
        }
        var actionButtons = [[String: String]]()
        if let buttons = buttons, !buttons.isEmpty {
            buttons.forEach { (button) in
                var dict = [String: String]()
                dict["caption"] = button.caption
                dict["action"] = button.action
                actionButtons.append(dict)
            }
            apnsOptions["buttons"] = actionButtons
        }
        if let action = action {
            apnsOptions["action"] = action
        }
        log("APNs DATA = \(apnsOptions)")
        return apnsOptions.isEmpty ? nil : apnsOptions
    }
    
    private var downloadTask: URLSessionDownloadTask? = nil
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "MySession")
        config.isDiscretionary = true
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    private func downloadAttachments(urlStr: String,  completion: @escaping (URL) -> (), completionOnError: @escaping () -> ()){
        
        guard let url = URL(string: urlStr) else {
            completionOnError()
            return
        }
        
        downloadTask = URLSession.shared.downloadTask(with: url)
        { (location, response, error) in
            self.log("downloadTask error: \(error.debugDescription)")
            if let location = location {
                let tmpDirectory = NSTemporaryDirectory()
                let tmpFile = "file://".appending(tmpDirectory).appending(url.lastPathComponent)
                
                let tmpUrl = URL(string: tmpFile)!
                try? FileManager.default.moveItem(at: location, to: tmpUrl)
                completion(tmpUrl)
            } else {
                completionOnError()
            }
        }
        
        DispatchQueue.global().async {
            self.downloadTask?.resume()
        }
    }
    
    private func getNotificationActionId(_ userInfo: [AnyHashable: Any]) -> String? {
        guard let action = userInfo["action"] as? [AnyHashable: Any],
            let pushActionId = action["action"] as? String else { return nil }
        return pushActionId
    }
    
    private func getPushId(_ userInfo: [AnyHashable: Any]) -> Int64? {
        guard let val = userInfo["aps"], let dic = val as? [AnyHashable: Any] else {
            log("Aps key not found in json")
            return nil
        }
        if let pushId = dic["pushId"] as? Int64 {
            log("Push Id: \(pushId)")
            return pushId
        } else if let pushIdStr = dic["pushId"] as? String, let pushId = Int64(pushIdStr) {
            log("Push Id: \(pushId)")
            return pushId
        } else {
            log("Push Id not found or has unknown type")
            return nil
        }
    }
    
    //MARK: -Permissions
    private func getPermissionForPushNotifications(completion: @escaping (Bool) -> ()) {
        log("GetPermissionForPushNotifications")
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { (granted, error) in
                self.log("Get Permission For PushNotifications with granted = \(granted)")
                self.trackNotificationPermissionsGranted(granted: granted)
                completion(granted)
                guard  granted  else { return }
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
            }
        } else {
            let settings = UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
            UIApplication.shared.registerUserNotificationSettings(settings)
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    
    private func trackNotificationPermissionsGranted(granted: Bool) {
        guard let userDefaults = UserDefaultsManager.userDefaults else {
            log("Error: UserDefaults in trackNotificationPermissionsGranted not found!")
            return
        }
        let val = userDefaults.value(forKey: Devino.isSubscribedFlag) as? Bool
        log("IsSubscribedFlag: \(String(describing: val)), Granted: \(granted)")
        guard  val != granted else { return }
        makeRequest(.usersSubscribtion(subscribed: granted))
        userDefaults.set(granted, forKey: Devino.isSubscribedFlag)
        userDefaults.synchronize()
        log("If current SubscribedFlag != Granted, saved Granted with value: \(granted))")
    }

    func showPushPermissionMsg() {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: "Push Notifications Permission Required", message: "Please enable push notifications permissions in settings.", preferredStyle: UIAlertController.Style.alert)
            let okAction = UIAlertAction(title: "Settings", style: .default, handler: {(cAlertAction) in
                //Redirect to Settings app
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            })
            let cancelAction = UIAlertAction(title: "Cancel", style: UIAlertAction.Style.cancel)
            alertController.addAction(cancelAction)
            alertController.addAction(okAction)
            UIApplication.shared.keyWindow?.rootViewController?.present(alertController, animated: true, completion: nil)
        }
    }
    
//MARK: -Base params
    
    typealias ParamKey = String
    typealias ParamValue = Any
    typealias Param = (ParamKey, ParamValue)
    
    private static var osVersion: Param {
        return Param("osVersion", UIDevice.current.systemVersion)
    }
    private static var appVersion: Param {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return Param("appVersion", appVersion ?? "1.0")
    }
    private static var language: Param {
        return Param("language", Locale.current.languageCode ?? "")
    }
    private static var reportedDateTimeUtc: Param {
        return Param("reportedDateTimeUtc", Date.ISOStringFromDate(date: Date()))
    }
    private static var subscribed: Param {
        return Param("subscribed", Devino.isUserNotificationsAvailable)
    }
    private static var platform: Param {
        return Param("platform", "IOS")
    }
    
//MARK: -API
    enum APIMethod {
        
        enum PushActionType: String {
            case delivered = "DELIVERED"
            case opened = "OPENED"
        }
        
        case usersData(email: String?, phone: String?, custom: [String: Any])
        case usersAppStart
        case usersEvent(eventName: String, eventData: [String: Any])
        case usersSubscribtion(subscribed: Bool)
        case usersSubscriptionStatus
        case usersGeo(long: Double, lat: Double)
        case pushEvent(pushToken: String, pushId: Int64, actionType: PushActionType, actionId: String?)
        case messages(title: String? = nil, text: String? = nil, badge: Int? = nil, validity: Int? = nil, priority: Priority = .realtime, silentPush: Bool? = nil, options: [String: Any]? = nil, apns: [String: Any]? = nil)
        
        var httpMethod: String {
            switch self {
            case .pushEvent,
                 .usersGeo,
                 .usersSubscribtion,
                 .usersEvent,
                 .usersAppStart,
                 .messages:
                return "POST"
            case .usersData:
                return "PUT"
            case .usersSubscriptionStatus:
                return "GET"
            }
        }
        
        var apiType: String {
            switch self {
            case .pushEvent,
                 .usersGeo,
                 .usersSubscribtion,
                 .usersSubscriptionStatus,
                 .usersEvent,
                 .usersAppStart,
                 .usersData:
                return "sdk"
            case .messages:
                return "api"
            }
        }
        
        //MARK: Create body params
        var params: [String: Any]? {
            switch self {
            case let .usersData(email, phone, custom):
                var dic: [String: Any] = buildDic(dict: ["customData": buildDic(dict: custom,
                                                                        Devino.osVersion,
                                                                        Devino.appVersion,
                                                                        Devino.language)
                                                        ], Devino.reportedDateTimeUtc)
                if let email = email {
                    dic["email"] = email
                }
                if let phone = phone {
                    dic["phone"] = phone
                }
                return dic
            case .usersAppStart:
                return buildDic(Devino.reportedDateTimeUtc,
                                Devino.appVersion,
                                Devino.osVersion,
                                Devino.platform,
                                Devino.language,
                                Devino.subscribed)
                
            case let .usersEvent(eventName, eventData):
                return buildDic(dict: ["eventName": eventName, "eventData": eventData], Devino.reportedDateTimeUtc)
                
            case let .usersSubscribtion(subscribed):
                return buildDic(dict: ["subscribed": subscribed], Devino.reportedDateTimeUtc)
                
            case .usersSubscriptionStatus:
                return [:]
                
            case let .usersGeo(long, lat):
                return buildDic(dict: ["longitude": long, "latitude": lat], Devino.reportedDateTimeUtc)
                
            case let .pushEvent(pushToken, pushId, actionType, actionId):
                var dic = buildDic(dict: ["pushToken": pushToken,
                                          "pushId": pushId,
                                          "actionType": actionType.rawValue], Devino.reportedDateTimeUtc)
                if let actionId = actionId {
                    dic["actionId"] = actionId
                }
                return dic
            case let .messages(title, text, badge, validity, priority, silentPush, options, apns):
                var dic = buildDic(dict: ["priority": priority.rawValue])
                if let pushToken = Devino.pushToken {
                    dic["to"] = pushToken
                }
                if let title = title {
                    dic["title"] = title
                }
                if let text = text {
                    dic["text"] = text
                }
                if let badge = badge {
                    dic["badge"] = badge
                }
                if let validity = validity {
                    dic["validity"] = validity
                }
                if let silentPush = silentPush {
                    dic["silentPush"] = silentPush
                }
                if let options = options {
                    dic["options"] = buildDic(dict: options)
                }
                if let apns = apns {
                    dic["apns"] = buildDic(dict: apns)
                }
                return dic
            }
        }
        
        private func buildDic(dict: [String: Any] = [:],  _ params: Param... ) -> [String: Any] {
            var dict = dict
            for param in params {
                dict[param.0] = param.1
            }
            return dict
        }
        
        //MARK: Create request URLs
        var path: String? {
            switch self {
            case .usersData:                return users("data")
            case .usersAppStart:            return users("app-start")
            case .usersEvent:               return users("event")
            case .usersGeo:                 return users("geo")
            case .usersSubscribtion:        return users("subscription")
            case .usersSubscriptionStatus:  return users("subscription/status")
            case .pushEvent:
                return "\(apiType)/messages/events"
            case .messages: return "\(apiType)/messages"
            }
        }
        
        private func users(_ event: String) -> String? {
            guard let pushToken = Devino.pushToken else {
                return nil
            }
            return "\(apiType)/users/\(pushToken)/\(event)"
        }
    }
    
    private var requestCounter = 1
    
//MARK: -Make Request:
    
    func makeRequest(_ meth: APIMethod, _ completionHandler: ((Data?, HTTPURLResponse?, Error?) -> Void)? = nil) {
    
        guard let userDefaults = UserDefaultsManager.userDefaults else {
            log("Error: UserDefaults in makeRequest not found!")
            return
        }
        guard let path = meth.path else { return }
        let applicationId = userDefaults.integer(forKey: Devino.appId)
    
        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        let apiRootUrl = userDefaults.string(forKey: Devino.apiRootUrl)
        urlComponents.host = apiRootUrl
        switch meth {
        case .usersSubscriptionStatus:
            urlComponents.path = "/push/\(path)"
            urlComponents.queryItems = [
               URLQueryItem(name: "applicationId", value: "\(applicationId)")
            ]
        default:
            urlComponents.path = "/push/\(path)"
        }
        
        guard let url = urlComponents.url else { fatalError("Could not create URL from components") }
        
        var request = URLRequest(url: url)
        request.httpMethod = meth.httpMethod
        request.allowsCellularAccess = true
        var headers = request.allHTTPHeaderFields ?? [:]
      
        if let key = userDefaults.string(forKey: Devino.configKeyFlag) {
            headers["Content-Type"] = "application/json"
            headers["X-Api-Key"] = "\(key)"  //X-Api-Key
        }
        request.allHTTPHeaderFields = headers
        log("Headers: \(headers)")

        do {
            var params = meth.params
            var apiParams: [Any]?
            switch meth {
            case .usersSubscriptionStatus:
                break
            default:
                if meth.apiType == "sdk" {
                    params?["applicationId"] = applicationId
                } else if meth.apiType == "api" {
                    params?["from"] = applicationId
                    apiParams = [params as Any]
                }
                request.httpBody = try JSONSerialization.data(withJSONObject: (meth.apiType == "sdk") ? (params as Any) : (apiParams as Any), options: JSONSerialization.WritingOptions())
            }
            
            guard let appGroupId = userDefaults.string(forKey: Devino.appGroupId) else {
                log("Error: makeRequest not found!")
                return
            }
            
            // Create and run a URLSession data task with our JSON encoded POST request
            let config = URLSessionConfiguration.default
            config.sharedContainerIdentifier = appGroupId
            config.allowsCellularAccess = true

            if #available(iOS 13.0, *) {
                config.allowsConstrainedNetworkAccess = true
                config.allowsExpensiveNetworkAccess = true
            }
            let session = URLSession(configuration: config)
            let count = requestCounter
            requestCounter += 1
            if let url = request.url?.absoluteURL {
                log("Request(\(count)): url[\(url)]")
            }
            if let body = request.httpBody {
                log("Body data: \(String(data: body, encoding: .utf8) ?? "no body data")")
            }
            let task = session.dataTask(with: request) { [weak self] (responseData, response, responseError) in
                DispatchQueue.main.async {
                    let httpResponse = response as? HTTPURLResponse
                    // APIs usually respond with the data you just sent in your POST request
                    if let data = responseData, let utf8Representation = String(data: data, encoding: .utf8) {
                        self?.log("Response(\(count)):[\(String(describing: httpResponse?.statusCode))]: \(utf8Representation)")
                        completionHandler?(data, httpResponse, nil)
                    } else if let error = responseError {
                        self?.log("Response Error = \(error.localizedDescription))")
                        self?.log("Response(\(count)):[\(String(describing: httpResponse?.statusCode))]: no readable data received in response")
                        completionHandler?(nil, nil, error)
                    }

                    if httpResponse == nil || httpResponse?.statusCode == 500 {
                        self?.needRepeatRequest(request: request)
                        return
                    } else if let statusCode = httpResponse?.statusCode, statusCode > 299 {
                        self?.needRepeatRequest(request: request)
                        return
                    }
                }
            }
            task.resume()
        } catch {
            log("Error: \(error)")
        }
    }
    
//MARK: -Make Repeate Request:
    
    private let concurrent = DispatchQueue(label: "Devino", attributes: .concurrent)
    private var failedRequestsCount = [URLRequest: Int]()
    var stopTimeRetry: DispatchTime?
    
    private func needRepeatRequest(request: URLRequest) {
        let val = failedRequestsCount[request] ?? 0
        let newVal = val + 1
        if newVal == 1 {
            stopTimeRetry = .now() + .seconds(60*60*24)
        }
        
        failedRequestsCount[request] = newVal
        
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        
        let task = session.dataTask(with: request) { [weak self] (responseData, response, responseError) in
            let httpResponse = response as? HTTPURLResponse
            // APIs usually respond with the data you just sent in your POST request
            if let data = responseData, let utf8Representation = String(data: data, encoding: .utf8) {
                self?.failedRequestsCount.removeValue(forKey: request)
                self?.log("Response: \(utf8Representation)")
            } else if let error = responseError {
                self?.log("Error \(error.localizedDescription)")
            } else {
                self?.log("No readable data received in response")
            }
        }
        
        let repeatTime: Int = newVal > 3 ? 60*60 : 60
        guard let stopTimeRetry = stopTimeRetry, stopTimeRetry > DispatchTime.now() + .seconds(repeatTime) else {
            log("The last correct response was received more than 24 hours ago. Retry requests have been stopped")
            self.stopTimeRetry = nil
            failedRequestsCount.removeAll()
            return
        }
        concurrent.asyncAfter(deadline: .now() + .seconds(repeatTime)) {
            if let url = request.url?.absoluteURL {
                self.log("REPEATE: url[\(url)]")
            }
            if let body = request.httpBody {
                self.log("Body data: \(String(data: body, encoding: .utf8) ?? "no body data")")
            }
            task.resume()
        }
    }
}

//MARK: -CLLocationManagerDelegate:

extension Devino: CLLocationManagerDelegate {
    
    @objc func startUpdateLocation() {
        if CLLocationManager.locationServicesEnabled() {
            switch CLLocationManager.authorizationStatus() {
            case .notDetermined, .restricted, .denied:
                log("Location No Access")
                showLocationPermissionMsg()
            case .authorizedAlways, .authorizedWhenInUse:
                log("Location Access")
                locManager.requestLocation()
            default:
                log("Location No Access (unknown)")
                break
            }
        } else {
            log("Location services are not enabled")
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let userLocation: CLLocation = locations[0] as CLLocation
        makeRequest(.usersGeo(long: userLocation.coordinate.longitude, lat: userLocation.coordinate.latitude)) { [weak self] (data, response, error) in
            guard let `self` = self else { return }
            if self.isSendPush {
                self.isSendPush = false
                self.makeRequest(.messages(title: "Ваши координаты:",
                text: "\(String(format: "%.7f", userLocation.coordinate.latitude)), \(String(format: "%.7f", userLocation.coordinate.longitude)), \(Date.ISOStringFromDate(date: Date()).convert())",
                priority: .low))
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log("Error location: \(error)")
    }

    private func showLocationPermissionMsg() {
        let alertController = UIAlertController(title: "Location Permission Required", message: "Please enable location permissions in settings.", preferredStyle: UIAlertController.Style.alert)
        let okAction = UIAlertAction(title: "Settings", style: .default, handler: {(cAlertAction) in
            //Redirect to Settings app
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        })
        let cancelAction = UIAlertAction(title: "Cancel", style: UIAlertAction.Style.cancel)
        alertController.addAction(cancelAction)
        alertController.addAction(okAction)
        UIApplication.shared.keyWindow?.rootViewController?.present(alertController, animated: true, completion: nil)
    }
}

//MARK: -URLSessionDelegate:

extension Devino: URLSessionDelegate {}

//MARK: -Models:

public class ActionButton {
    var caption: String //name button
    var action: String //urls/deep link
    
    public init(caption: String, action: String) {
        self.caption = caption
        self.action = action
    }
}

public enum Priority: String {
    case mediul = "MEDIUM"
    case low = "LOW"
    case high = "HIGH"
    case realtime = "REALTIME"
}

public enum Badge: Int {
    case zero = 0
    case one = 1
}

private enum ErrorHandler: Error {
    case failureJSONData
    case failureServerData
}

 //MARK: -UserDefaults

public class UserDefaultsManager: NSObject {
    public static var userDefaults: UserDefaults?
}
