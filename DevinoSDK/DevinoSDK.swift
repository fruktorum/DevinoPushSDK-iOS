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

fileprivate extension Date {
    static func ISOStringFromDate(date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        dateFormatter.timeZone = NSTimeZone(abbreviation: "UTC") as! TimeZone
        return dateFormatter.string(from: date).appending("Z")
    }
}

fileprivate extension Dictionary where Key: ExpressibleByStringLiteral, Value: Any  {
    
    func string(_ key: Key) -> String? {
        guard let val = self[key] as? String else { return nil }
        return val
    }
}

fileprivate extension UserDefaults {
    static func isFirstLaunch() -> Bool {
        let hasBeenLaunchedBeforeFlag = "DevinoHasBeenLaunchedBeforeFlag"
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: hasBeenLaunchedBeforeFlag)
        if (isFirstLaunch) {
            UserDefaults.standard.set(true, forKey: hasBeenLaunchedBeforeFlag)
            UserDefaults.standard.synchronize()
        }
        return isFirstLaunch
    }
}

public final class Devino : NSObject {
    private static let deviceTokenFlag = "DevinoDeviceTokenFlag"
    private static let isSubscribedFlag = "DevinoIsSubscribedFlag"
 
    public struct Configuration {
        // Апи ключ Devino
        public let key: String
        // Интервал в минутах для обновления данных геолокации
        public let geoDataSendindInterval: Int
        // Сервер
        public let apiRootUrl:String
        // Порт
        public let apiRootPort: Int?
        
        public init(key: String, geoDataSendindInterval: Int = 0, apiRootUrl:String = "194.226.179.156", apiRootPort: Int? =  6602) {
            self.key = key
            self.geoDataSendindInterval = geoDataSendindInterval
            self.apiRootUrl = apiRootUrl
            self.apiRootPort = apiRootPort
        }
    }
    public var debug: Bool = false
    public var logger: ((String) -> Void)? = nil
    
    func log(_ str: String) {
        logger?(str)
    }
    public static var shared = Devino()
    
    private static var pushToken: String? {
        return UserDefaults.standard.string(forKey: deviceTokenFlag)
    }
    
    private static var applicationId: String? {
        return Bundle.main.bundleIdentifier
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
    private static var isUserNotificationsAvailable = false
    
    private func updateIsUserNotificationsAvailable(completion: @escaping (Bool) -> () ) {
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                Devino.isUserNotificationsAvailable = settings.authorizationStatus == .authorized
                completion(Devino.isUserNotificationsAvailable)
            }
        } else {
            if let settings = UIApplication.shared.currentUserNotificationSettings {
                Devino.isUserNotificationsAvailable = settings.types != []//.none
                completion(Devino.isUserNotificationsAvailable)
            } else {
                Devino.isUserNotificationsAvailable = false
                completion(Devino.isUserNotificationsAvailable)
            }
        }
    }
    
    //MARK: Public
    public func trackAppLaunch() {
        guard Devino.pushToken != nil else { return }
        updateIsUserNotificationsAvailable { subscribed in
            self.makeRequest(.usersAppStart)
        }
        
        if let existedIsSubscribedFlag = UserDefaults.standard.value(forKey: Devino.isSubscribedFlag) as? Bool, existedIsSubscribedFlag != UIApplication.shared.isRegisteredForRemoteNotifications  {
            makeRequest(.usersSubscribtion(subscribed: Devino.isUserNotificationsAvailable))
        }
    }
    
    public func trackNotificationPermissionsGranted(granted: Bool) {
        let val = UserDefaults.standard.value(forKey: Devino.isSubscribedFlag) as? Bool
        Devino.isUserNotificationsAvailable = granted
        guard  val != granted else { return }
        
        makeRequest(.usersSubscribtion(subscribed: granted))
        UserDefaults.standard.set(granted, forKey: Devino.isSubscribedFlag)
        UserDefaults.standard.synchronize()
    }
    
    public func trackLaunchWithOptions(_ options : [UIApplication.LaunchOptionsKey: Any]?) {
        trackAppLaunch()
        
        if let time = configuration?.geoDataSendindInterval, time > 0, CLLocationManager.locationServicesEnabled() {
            trackLocation()
        }
        
        guard let notification = options?[UIApplication.LaunchOptionsKey.remoteNotification] as? [AnyHashable: Any], let pushId = getPushId(notification) else  { return }
    }
    
    public func trackReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        guard Devino.isUserNotificationsAvailable else { return }
        setLocationNotification(userInfo)
    }
    
    
    public func setUserData(phone: String?, email: String?) {
        self.email = email
        self.phone = phone
        
        makeRequest(.usersData(email: email, phone: phone, custom: [:]))
    }
    
    @available(iOS 10.0, *)
    public func trackNotificationResponse(_ response: UNNotificationResponse) {
        log("\nNOTIFICATION ACTION: \(response.actionIdentifier)")
        
        let ui = response.notification.request.content.userInfo
        guard  let pushId = getPushId(ui) else { return }
        
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            makeRequest(.pushEvent(pushId: pushId, actionType: .opened, actionId: getNotificationActionId(ui)))
        } else {
            makeRequest(.pushEvent(pushId: pushId, actionType: .opened, actionId: response.actionIdentifier))
        }
    }
    
    public func trackAppTerminated(){
        makeRequest(.usersEvent(eventName: "device-terminated", eventData: [:]))
    }
    
    // For ios <10
    public func trackLocalNotification(_ notification: UILocalNotification, with identifier: String? ) {
        log("\nNOTIFICATION ACTION: \(identifier)")
        
        guard let ui = notification.userInfo, let pushId = getPushId(ui) else { return }
        
        if let identifier = identifier {
            makeRequest(.pushEvent(pushId: pushId, actionType: .opened, actionId: identifier))
        } else {
            makeRequest(.pushEvent(pushId: pushId, actionType: .opened, actionId: getNotificationActionId(ui)))
        }
    }
    
    public func trackEvent(name: String, params: [String: Any] = [:]) {
        makeRequest(.usersEvent(eventName: name, eventData: params))
    }
    
    public func activate(with config: Configuration) {
        configuration = config
    }
    
    public func trackLocation() {
        guard let time = configuration?.geoDataSendindInterval, time > 0 else { return }
        
        locManager.desiredAccuracy = kCLLocationAccuracyBest
        locManager.requestAlwaysAuthorization()
        
        timer = Timer.scheduledTimer(timeInterval: TimeInterval(time * 60), target: self,   selector: (#selector(Devino.startUpdateLocation)), userInfo: nil, repeats: true)
    }
    
    public func registerForNotification(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        
        let existedToken = UserDefaults.standard.string(forKey: Devino.deviceTokenFlag)
        
        guard existedToken != token  else { return }
        
        UserDefaults.standard.set(token, forKey: Devino.deviceTokenFlag)
        UserDefaults.standard.synchronize()
        
        if existedToken == nil {
            makeRequest(.usersData(email: email, phone: phone, custom: [:]))
        }
    }
    
    //MARK: Private
    private func notificationIOS9AppIsActive(_ userInfo: [AnyHashable: Any]) {
        guard UIApplication.shared.applicationState == .active else { return }
        
        guard let val = userInfo["aps"],
            let dic = val as? [AnyHashable: Any],
            let devino = dic["devino"] as? [String: Any],
            let alert = devino["alert"] as? [String: Any],
            let pushId = dic["pushId"] as? Int64
            else { return  }
        
        let alertVC = UIAlertController(title: alert.string("title"), message: alert.string("body"), preferredStyle: UIAlertController.Style.alert)
        
        if let actions = devino["actions"] as? [[String: String]]  {
            for act in actions {
                guard let title = act.string("title"),
                    let actIdent = act.string("action") else { continue }
                
                let notAct = UIAlertAction(title: title, style: .default, handler: { _ in
                    self.makeRequest(.pushEvent(pushId: pushId, actionType: .opened, actionId: actIdent))
                })
                alertVC.addAction(notAct)
            }
        }
        
        alertVC.addAction(UIAlertAction(title: "Закрыть", style: .cancel, handler: nil))
        
        UIApplication.shared.keyWindow?.rootViewController?.present(alertVC, animated: true, completion: {
            self.log("\nPUSH RECIVED: \(userInfo)")
            self.makeRequest(.pushEvent(pushId: pushId, actionType: .delivered, actionId: nil))
        })
    }
    
    private func setLocationNotification(_ userInfo: [AnyHashable: Any]) {
        guard let val = userInfo["aps"],
            let dic = val as? [AnyHashable: Any],
            let devino = dic["devino"] as? [String: Any],
            let pushId = dic["pushId"] as? Int64
            else { return  }
        
        if let silent = devino["silent"] as? Bool, silent {
            makeRequest(.pushEvent(pushId: pushId, actionType: .delivered, actionId: nil))
            return
        }
        
        guard let alert = devino["alert"] as? [String: Any] else { return }
        
        
        if #available(iOS 10.0, *) {} else {
            if UIApplication.shared.applicationState == .active {
                notificationIOS9AppIsActive(userInfo)
                return
            }
        }
        
        var hasActions = false
        if let actions = devino["actions"] as? [[String: String]] {
            if #available(iOS 10.0, *) {
                
                var notActs = [UNNotificationAction]()
                
                for act in actions {
                    guard let title = act.string("title"),
                        let actIdent = act.string("action") else { continue }
                    
                    let notAct = UNNotificationAction(identifier: actIdent,
                                                      title: title,
                                                      options: [.foreground])
                    notActs.append(notAct)
                    hasActions = true
                }
                
                if notActs.count > 0 {
                    let newsCategory = UNNotificationCategory(identifier: "CAT1",
                                                              actions: notActs,
                                                              intentIdentifiers: [],
                                                              options: [])
                    UNUserNotificationCenter.current().setNotificationCategories([newsCategory])
                }
            } else {
                
                var notActs = [UIMutableUserNotificationAction]()
                
                for act in actions {
                    guard let title = act.string("title"),
                        let actIdent = act.string("action") else { continue }
                    
                    let notAct = UIMutableUserNotificationAction()
                    notAct.identifier = actIdent
                    notAct.title = title
                    notAct.activationMode = UIUserNotificationActivationMode.foreground
                    notActs.append(notAct)
                    hasActions = true
                }
                
                let counterCategory = UIMutableUserNotificationCategory()
                counterCategory.identifier = "CAT1"
                
                if notActs.count > 0 {
                    counterCategory.setActions(notActs,  for: UIUserNotificationActionContext.default)
                    counterCategory.setActions(notActs,  for: UIUserNotificationActionContext.minimal)
                    
                    let settings = UIUserNotificationSettings(types: [.badge, .sound, .alert],
                                                              categories: [counterCategory])
                    UIApplication.shared.registerUserNotificationSettings(settings)
                }
            }
            
            
        }
        
        let notification = UILocalNotification()
        notification.alertBody = alert.string("body")
        notification.soundName = alert.string("sound") ?? UILocalNotificationDefaultSoundName
        notification.fireDate = Date()
        notification.category = hasActions ? "CAT1" : ""
        notification.alertTitle = alert.string("title")
        notification.userInfo = userInfo
        
        if let mediaUrlStr = devino["media-url"] as? String,  #available(iOS 10.0, *) {
            
            downloadAttachments(urlStr: mediaUrlStr, completion: { (tempUrl) in
                let content = UNMutableNotificationContent()
                content.title = alert.string("title") ?? ""
                content.body = alert.string("body") ?? ""
                content.userInfo = userInfo
                content.categoryIdentifier = hasActions ? "CAT1" : ""
                let attachment = try! UNNotificationAttachment(identifier: "image", url: tempUrl, options: .none)
                
                content.attachments = [attachment]
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                let request = UNNotificationRequest(identifier: "notification.id.01", content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
                self.log("\nPUSH RECIVED: \(userInfo)")
                self.makeRequest(.pushEvent(pushId: pushId, actionType: .delivered, actionId: nil))
            }) {
                UIApplication.shared.scheduleLocalNotification(notification)
                self.log("\nPUSH RECIVED: \(userInfo)")
                self.makeRequest(.pushEvent(pushId: pushId, actionType: .delivered, actionId: nil))
            }
        } else {
            
            UIApplication.shared.scheduleLocalNotification(notification)
            log("\nPUSH RECIVED: \(userInfo)")
            makeRequest(.pushEvent(pushId: pushId, actionType: .delivered, actionId: nil))
        }
    }
    
    
    private var downloadTask:URLSessionDownloadTask? = nil
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "MySession")
        config.isDiscretionary = true
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    private func downloadAttachments(urlStr: String,  completion: @escaping (URL) -> (), completionOnError: @escaping () -> () ){
        
        guard let url = URL(string: urlStr) else {
            completionOnError()
            return
        }
        
        downloadTask = URLSession.shared.downloadTask(with: url)
        { (location, response, error) in
            print(error.debugDescription)
            print(error)
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
        guard let dic = userInfo["aps"] as? [AnyHashable: Any],
            let devino = dic["devino"] as? [String: Any],
            let pushActionId = devino["pushActionId"] as? String else { return nil }
        
        return pushActionId
    }
    
    private func getPushId(_ userInfo: [AnyHashable: Any]) -> Int64? {
        guard let val = userInfo["aps"],
            let dic = val as? [AnyHashable: Any],
            let pushId = dic["pushId"] as? Int64 else { return nil }
        
        return pushId
    }
 
    //MARK: Init
    private override init() {  }
    
    //MARK: BASE PARAMS
    typealias ParamKey = String
    typealias ParamValue = Any
    typealias Param = (ParamKey, ParamValue)
    
    private static var osVersion: Param {
        return Param("osVersion", UIDevice.current.systemVersion)
    }
    private static var appVersion: Param {
        return Param("appVersion", "1.0")
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
    
    //MARK: API
    private enum APIMethod {
        
        enum PushActionType: String {
            case delivered = "DELIVERED"
            case opened = "OPENED"
        }
        
        case usersData(email: String?, phone: String?, custom: [String: Any])
        case usersAppStart
        case usersEvent(eventName: String, eventData: [String: Any])
        case usersSubscribtion(subscribed: Bool)
        case usersGeo(long: Double, lat: Double)
        case pushEvent(pushId: Int64, actionType: PushActionType, actionId: String?)
        
        var httpMethod: String {
            switch self {
            case .pushEvent,
                 .usersGeo,
                 .usersSubscribtion,
                 .usersEvent,
                 .usersAppStart:
                return "POST"
            case .usersData:
                return "PUT"
            }
            
        }
        
        private func buildDic(dict:[String: Any] = [:],  _ params: Param... ) -> [String: Any] {
            var dict = dict
            for param in params {
                dict[param.0] = param.1
            }
            return dict
        }
        
        var params: [String: Any]? {
            switch self {
            case let .usersData(email, phone, custom):
                var dic: [String: Any] = buildDic(dict: ["customData" : buildDic(dict: custom,
                                                                        Devino.osVersion,
                                                                        Devino.appVersion,
                                                                        Devino.language)
                                                        ], Devino.reportedDateTimeUtc)
                if let applicationId = Devino.applicationId {
                    dic["applicationId"] = applicationId
                }
                if let email = email {
                    dic["email"] = email
                }
                if let phone = phone {
                    dic["phone"] = phone
                }
                return dic
            case .usersAppStart :
                return buildDic(Devino.platform,
                                Devino.reportedDateTimeUtc,
                                Devino.osVersion,
                                Devino.appVersion,
                                Devino.language,
                                Devino.subscribed)
                
            case let .usersEvent(eventName, eventData):
                return buildDic(dict: ["eventName" : eventName, "eventData": eventData], Devino.reportedDateTimeUtc)
                
            case let .usersSubscribtion(subscribed):
                return buildDic(dict: ["subscribed" : subscribed], Devino.reportedDateTimeUtc)
                
            case let .usersGeo(long, lat):
                return buildDic(dict: ["longitude" : long, "latitude": lat], Devino.reportedDateTimeUtc)
                
            case let .pushEvent(pushId, actionType, actionId):
                var dic = buildDic(dict: ["pushId": pushId,
                                          "actionType": actionType.rawValue], Devino.reportedDateTimeUtc)
                if let actionId = actionId {
                    dic["actionId"] = actionId
                }
                if let token = Devino.pushToken {
                    dic["pushToken"] = token
                }
                return dic
            }
        }
        
        private func users(_ event: String) -> String? {
            guard let pushToken = Devino.pushToken else {
                return nil
            }
            return "/users/\(pushToken)/\(event)"
        }
        
        var path: String? {
            switch self {
            case .usersData:         return users("data")
            case .usersAppStart:     return users("app-start")
            case .usersEvent:        return users("event")
            case .usersGeo:          return users("geo")
            case .usersSubscribtion: return users("subscription")
            case .pushEvent:
                guard let pushToken = Devino.pushToken else { return nil  }
                return "/push-events"
            }
        }
    }
    private var requestCounter = 1
    //MAKR: Networking
    private func makeRequest(_ meth: APIMethod ) {
        guard let configuration = configuration else {
            log("Not Configured")
            return }
        
        guard let path = meth.path  else {
            return
        }
        
        var urlComponents = URLComponents()
        urlComponents.scheme = "http"
        urlComponents.host = configuration.apiRootUrl
        urlComponents.port = configuration.apiRootPort
        urlComponents.path = "/v1\(path)"
        guard let url = urlComponents.url else { fatalError("Could not create URL from components") }
        
        var request = URLRequest(url: url)
        request.httpMethod = meth.httpMethod
        var headers = request.allHTTPHeaderFields ?? [:]
        headers["Content-Type"] = "application/json"
        headers["Authorization"] = configuration.key
        request.allHTTPHeaderFields = headers
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: meth.params,
                                                          options: JSONSerialization.WritingOptions())
            
            // Create and run a URLSession data task with our JSON encoded POST request
            let config = URLSessionConfiguration.default
            let session = URLSession(configuration: config)
            
            let count = requestCounter
            requestCounter += 1
            if let url = request.url?.absoluteURL {
                log("\n\nrequest(\(count)): url[\(url)] \n \(String(data: request.httpBody!, encoding: .utf8) ?? "no body data")")
            }
            
            let task = session.dataTask(with: request) {[weak self] (responseData, response, responseError) in
                let httpResponse = response as? HTTPURLResponse
                 
                // APIs usually respond with the data you just sent in your POST request
                if let data = responseData, let utf8Representation = String(data: data, encoding: .utf8) {
                    self?.log("\nresponse(\(count)):[\(httpResponse?.statusCode)]: \(utf8Representation)")
                } else {
                    self?.log("\nresponse(\(count)):[\(httpResponse?.statusCode)]: no readable data received in response")
                }
                
                if  httpResponse == nil || httpResponse?.statusCode == 500  {
                    self?.needRepeatRequest(request: request)
                    return
                }
            }
            task.resume()
        } catch {
            log("ERROR: \(error)")
        }
    }
    
    private let concurrent = DispatchQueue(label: "Devino", attributes: .concurrent)
    
    private var failedRequestsCount = [URLRequest: Int]()
    
    private func needRepeatRequest(request: URLRequest) {
        
        let val = failedRequestsCount[request] ?? 0
        let newVal = val + 1
        
        failedRequestsCount[request] = newVal
        
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        let task = session.dataTask(with: request) { [weak self] (responseData, response, responseError) in
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 500  {
                self?.needRepeatRequest(request: request)
                return
            }
            
            // APIs usually respond with the data you just sent in your POST request
            if let data = responseData, let utf8Representation = String(data: data, encoding: .utf8) {
                self?.log("\nresponse: \(utf8Representation)")
            } else {
                print("no readable data received in response")
            }
        }
        
        let repeatTime: Int = newVal > 3 ? 60*60 : 2
        
        log("\n\n repeat №(\(newVal)) after \(repeatTime) sec ")
        
        concurrent.asyncAfter(deadline: .now() + .seconds(repeatTime)) {
            if let url = request.url?.absoluteURL {
                self.log("\nREPEATE: url[\(url)] \n \(String(data: request.httpBody!, encoding: .utf8) ?? "no body data")")
            }
            task.resume()
        }
    }
}

extension Devino : CLLocationManagerDelegate {
    @objc func startUpdateLocation() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        locManager.requestLocation()
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let userLocation:CLLocation = locations[0] as CLLocation
        
        makeRequest(.usersGeo(long: userLocation.coordinate.longitude,
                              lat: userLocation.coordinate.latitude))
        
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error)
    {
        print("Error \(error)")
    }
}

extension Devino : URLSessionDelegate{
    
}
