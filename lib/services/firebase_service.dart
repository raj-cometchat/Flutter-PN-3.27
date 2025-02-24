import 'dart:async';
import 'dart:convert';

import 'package:cometchat_calls_uikit/cometchat_calls_uikit.dart';
import 'package:cometchat_chat_uikit/cometchat_chat_uikit.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/call_action.dart';
import '../models/call_type.dart';
import '../models/notification_data_model.dart';
import '../models/notification_message_type_constants.dart';
import '../models/payload_data.dart';
import '../services/shared_perferences.dart';
import '../consts.dart';
import '../firebase_options.dart';
import 'cometchat_service.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

// Initialize notification settings
Future<void> initNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@drawable/notification_icon');

  const DarwinInitializationSettings initializationSettingsIOS =
  DarwinInitializationSettings();

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: handleNotificationTap,
  );
}

// Background message handler
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage rMessage) async {
  _showNotification(rMessage.data, rMessage);
  await displayIncomingCall(rMessage);
}

void _showNotification(Map<String, dynamic> data, RemoteMessage msg) async {
  // Check if notification is already initialized
  await initNotifications();

  // Create notification channel for Android
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    importance: Importance.max,
    playSound: true,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  AndroidNotificationDetails androidPlatformChannelSpecifics =
  const AndroidNotificationDetails(
    'high_importance_channel',
    'High Importance Notifications',
    channelDescription: 'This channel is used for important notifications.',
    importance: Importance.max,
    priority: Priority.high,
    icon: '@drawable/notification_icon',
    playSound: true,
    enableLights: true,
    enableVibration: true,
  );

  NotificationDetails platformChannelSpecifics =
  NotificationDetails(android: androidPlatformChannelSpecifics);

  String jsonPayload = jsonEncode(msg.data);

  if (msg.data["type"] != null && msg.data["type"] == "call") {
    return;
  }

  int? id;
  try {
    id = int.parse(data["tag"] ?? "0");
  } catch (e) {
    id = 0;
    debugPrint("Error while parsing notification id ${e.toString()}");
  }

  try {
    await flutterLocalNotificationsPlugin.show(
      id,
      data['title'],
      data['body'],
      platformChannelSpecifics,
      payload: jsonPayload,
    );
  } catch (e) {
    debugPrint("Error showing notification: ${e.toString()}");
  }
}

void handleNotificationTap(NotificationResponse response) async {
  if (response.payload != null) {
    final body = jsonDecode(response.payload!) as Map<String, dynamic>;
    NotificationDataModel notificationDataModel =
    NotificationDataModel.fromJson(body);

    User? sendUser;
    Group? sendGroup;

    if (notificationDataModel.receiverType == "user") {
      final uid = notificationDataModel.sender ?? '';
      await CometChat.getUser(
        uid,
        onSuccess: (user) {
          debugPrint("User fetched $user");
          sendUser = user;
        },
        onError: (exception) {
          if (kDebugMode) {
            debugPrint("Error while retrieving user ${exception.message}");
          }
        },
      );
    } else if (notificationDataModel.receiverType == "group") {
      final guid = notificationDataModel.receiver ?? '';
      await CometChat.getGroup(
        guid,
        onSuccess: (group) {
          sendGroup = group;
        },
        onError: (exception) {
          if (kDebugMode) {
            debugPrint("Error while retrieving group ${exception.message}");
          }
        },
      );
    }

    if (notificationDataModel.type == NotificationMessageTypeConstants.chat &&
        (notificationDataModel.receiverType == ReceiverTypeConstants.user &&
            sendUser != null) ||
        (notificationDataModel.receiverType == ReceiverTypeConstants.group &&
            sendGroup != null)) {
      if (CallNavigationContext.navigatorKey.currentContext != null &&
          CallNavigationContext.navigatorKey.currentContext!.mounted) {
        Future.delayed(const Duration(milliseconds: 100), () {
          Navigator.of(CallNavigationContext.navigatorKey.currentContext!).push(
            MaterialPageRoute(
              builder: (context) => CometChatMessages(
                user: sendUser,
                group: sendGroup,
              ),
            ),
          );
        });
      }
    }
  }
}

String? activeCallSession;

Future<void> displayIncomingCall(RemoteMessage rMessage) async {
  Map<String, dynamic> ccMessage = rMessage.data;
  PayloadData callPayload = PayloadData.fromJson(ccMessage);
  String messageCategory = callPayload.type ?? "";

  if (messageCategory == 'call') {
    CallAction callAction = callPayload.callAction!;
    String uuid = callPayload.sessionId ?? "";
    final callUUID = uuid;
    String callerName = callPayload.senderName ?? "";
    CallType callType = callPayload.callType ?? CallType.none;

    if (callAction == CallAction.initiated &&
        (callPayload.sentAt != null &&
            DateTime.now()
                .isBefore(callPayload.sentAt!.add(const Duration(seconds: 40))))) {
      CallKitParams callKitParams = CallKitParams(
        id: callUUID,
        nameCaller: callerName,
        appName: 'notification_new',
        type: (callType == CallType.audio) ? 0 : 1,
        textAccept: 'Accept',
        textDecline: 'Decline',
        duration: 40000,
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          backgroundColor: '#0955fa',
          actionColor: '#4CAF50',
          incomingCallNotificationChannelName: "Incoming Call",
          isShowFullLockedScreen: false,
        ),
        ios: const IOSParams(
          handleType: 'generic',
          supportsVideo: true,
          maximumCallGroups: 2,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'default',
          audioSessionActive: true,
          audioSessionPreferredSampleRate: 44100.0,
          audioSessionPreferredIOBufferDuration: 0.005,
          supportsDTMF: true,
          supportsHolding: true,
          supportsGrouping: false,
          supportsUngrouping: false,
        ),
      );

      await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);

      FlutterCallkitIncoming.onEvent.listen(
            (CallEvent? callEvent) async {
          switch (callEvent?.event) {
            case Event.actionCallIncoming:
              SharedPreferencesClass.init();
              break;
            case Event.actionCallAccept:
              String sessionId = callEvent?.body["id"];
              String callType = callEvent?.body["type"] == 0 ? "audio" : "video";

              SharedPreferencesClass.setString("SessionId", sessionId);
              SharedPreferencesClass.setString("callType", callType);

              Future.delayed(const Duration(milliseconds: 200), () {
                if (CallNavigationContext.navigatorKey.currentContext != null &&
                    CallNavigationContext.navigatorKey.currentContext!.mounted) {
                  Navigator.push(
                    CallNavigationContext.navigatorKey.currentContext!,
                    MaterialPageRoute(
                      builder: (context) => CometChatOngoingCall(
                        sessionId: sessionId,
                        callSettingsBuilder: (CallSettingsBuilder()
                          ..enableDefaultLayout = true
                          ..setAudioOnlyCall = (callType == "audio")),
                      ),
                    ),
                  );
                }
              });
              break;
            case Event.actionCallDecline:
              CometChatService().init();
              CometChatUIKitCalls.rejectCall(
                callEvent?.body["id"],
                CallStatusConstants.rejected,
                onSuccess: (Call call) async {
                  call.category = MessageCategoryConstants.call;
                  CometChatCallEvents.ccCallRejected(call);
                  await FlutterCallkitIncoming.endCall(callEvent?.body['id']);
                  debugPrint('incoming call was rejected');
                },
                onError: (e) {
                  debugPrint(
                      "Unable to end call from incoming call screen ${e.message}");
                },
              );
              break;
            case Event.actionCallEnded:
              await FlutterCallkitIncoming.endCall(callEvent?.body['id']);
              break;
            default:
              break;
          }
        },
        cancelOnError: false,
        onDone: () {
          debugPrint('FlutterCallkitIncoming.onEvent: done');
        },
        onError: (e) {
          debugPrint('FlutterCallkitIncoming.onEvent:error ${e.toString()}');
        },
      );
    } else if (callAction == CallAction.cancelled ||
        callAction == CallAction.unanswered) {
      if (callPayload.sessionId != null) {
        await FlutterCallkitIncoming.endCall(callPayload.sessionId ?? "");
        activeCallSession = null;
      }
    }
  }
}

class FirebaseService {
  late final FirebaseMessaging _firebaseMessaging;
  late final NotificationSettings _settings;

  Future<void> init(BuildContext context) async {
    try {
      // Initialize Firebase
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Initialize notifications
      await initNotifications();

      // Get FirebaseMessaging instance
      _firebaseMessaging = FirebaseMessaging.instance;

      // Request permissions
      await requestPermissions();

      // Setup notification listeners
      if (context.mounted) await initListeners(context);

      // Fetch and register FCM token
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        PNRegistry.registerPNService(token, true, false);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Firebase initialization error: $e');
      }
    }
  }

  Future<void> requestPermissions() async {
    try {
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        provisional: false,
        sound: true,
      );
      _settings = settings;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error requesting permissions: $e');
      }
    }
  }

  Future<void> initListeners(BuildContext context) async {
    try {
      if (_settings.authorizationStatus == AuthorizationStatus.authorized) {
        // For handling notification when the app is in the background
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

        // Refresh token listener
        _firebaseMessaging.onTokenRefresh.listen((String token) async {
          if (kDebugMode) {
            debugPrint('Token refreshed: $token');
          }
          PNRegistry.registerPNService(token, true, false);
        });

        // Handle notification click when app is in background
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
          openNotification(context, message);
        });

        // Handle foreground messages
        FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
          if (message.notification != null) {
            openNotification(context, message);
          } else if (message.data.isNotEmpty) {
            _showNotification(message.data, message);
          }
        });

        // Handle initial message when app is launched from terminated state
        FirebaseMessaging.instance
            .getInitialMessage()
            .then((RemoteMessage? message) async {
          if (message != null) {
            openNotification(context, message);
          }
        });

        openFromTerminatedState(context);
      } else {
        if (kDebugMode) {
          debugPrint('User declined or has not accepted permission');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error initializing listeners: $e');
      }
    }
  }

  Future<void> openNotification(BuildContext context, RemoteMessage? message) async {
    if (message != null) {
      Map<String, dynamic> data = message.data;
      PayloadData payload = PayloadData.fromJson(data);
      String messageCategory = payload.type ?? "";
      final receiverType = payload.receiverType ?? "";

      User? sendUser;
      Group? sendGroup;

      if (receiverType == "user") {
        final uid = payload.sender ?? '';
        await CometChat.getUser(
          uid,
          onSuccess: (user) {
            debugPrint("User fetched $user");
            sendUser = user;
          },
          onError: (exception) {
            if (kDebugMode) {
              debugPrint("Error while retrieving user ${exception.message}");
            }
          },
        );
      } else if (receiverType == "group") {
        final guid = payload.receiver ?? '';
        await CometChat.getGroup(
          guid,
          onSuccess: (group) {
            sendGroup = group;
          },
          onError: (exception) {
            if (kDebugMode) {
              debugPrint("Error while retrieving group ${exception.message}");
            }
          },
        );
      }

      if (messageCategory == NotificationMessageTypeConstants.call) {
        CallAction callAction = payload.callAction!;
        String uuid = payload.sessionId ?? "";

        if (callAction == CallAction.initiated) {
          if (receiverType == ReceiverTypeConstants.user && sendUser != null) {
            Call call = Call(
                sessionId: uuid,
                receiverUid: sendUser?.uid ?? "",
                type: payload.callType?.value ?? "",
                receiverType: receiverType);

            if (context.mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => CometChatIncomingCall(
                    call: call,
                    user: sendUser,
                  ),
                ),
              );
            }
          }
        } else if (receiverType == ReceiverTypeConstants.group &&
            sendGroup != null) {
          if (kDebugMode) {
            debugPrint("we are in group call");
          }
        } else if (callAction == CallAction.cancelled) {
          if (activeCallSession != null) {
            await FlutterCallkitIncoming.endCall(activeCallSession!);
            activeCallSession = null;
          }
        }
      }

      // Navigating to the chat screen when messageCategory is message
      if (messageCategory == NotificationMessageTypeConstants.chat &&
          (receiverType == ReceiverTypeConstants.user &&
              sendUser != null) ||
          (receiverType == ReceiverTypeConstants.group && sendGroup != null)) {
        if (context.mounted) {
          Future.delayed(const Duration(seconds: 2), () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => CometChatMessages(
                  user: sendUser,
                  group: sendGroup,
                ),
              ),
            );
          });
        }
      }
    }
  }

  // Deletes fcm token
  Future<void> deleteToken() async {
    try {
      await _firebaseMessaging.deleteToken();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error while deleting token $e');
      }
    }
  }

  // Check for navigation when app opens from terminated state when we accept call
  openFromTerminatedState(BuildContext context) {
    final sessionID = SharedPreferencesClass.getString("SessionId");
    final callType = SharedPreferencesClass.getString("callType");

    if (sessionID.isNotEmpty) {
      CallSettingsBuilder callSettingsBuilder = (CallSettingsBuilder()
        ..enableDefaultLayout = true
        ..setAudioOnlyCall = (callType == CallType.audio.value));
      CometChatUIKitCalls.acceptCall(sessionID, onSuccess: (Call call) {
        call.category = MessageCategoryConstants.call;
        CometChatCallEvents.ccCallAccepted(call);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CometChatOngoingCall(
              callSettingsBuilder: callSettingsBuilder,
              sessionId: sessionID,
              callWorkFlow: CallWorkFlow.defaultCalling,
            ),
          ),
        );
      }, onError: (e) {
        debugPrint(
            "Unable to accept call from incoming call screen ${e.details}");
      });
    }
  }

  // Check for navigation when app opens from background state when we accept call
  resumeCallListeners(BuildContext context) async {
    FlutterCallkitIncoming.onEvent.listen(
          (CallEvent? callEvent) async {
        switch (callEvent?.event) {
          case Event.actionCallIncoming:
            CometChatUIKitCalls.init(
                CometChatConstants.appId, CometChatConstants.region,
                onSuccess: (p0) {
                  debugPrint("CometChatUIKitCalls initialized successfully");
                }, onError: (e) {
              debugPrint("CometChatUIKitCalls failed ${e.message}");
            });
            activeCallSession = callEvent?.body["id"];
            break;
          case Event.actionCallAccept:
            final callType = callEvent?.body["type"];
            CallSettingsBuilder callSettingsBuilder = (CallSettingsBuilder()
              ..enableDefaultLayout = true
              ..setAudioOnlyCall = (callType == CallType.audio.value));

            CometChatUIKitCalls.acceptCall(callEvent!.body["id"],
                onSuccess: (Call call) {
                  call.category = MessageCategoryConstants.call;
                  CometChatCallEvents.ccCallAccepted(call);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CometChatOngoingCall(
                        callSettingsBuilder: callSettingsBuilder,
                        sessionId: callEvent.body["id"],
                      ),
                    ),
                  );
                }, onError: (e) {
                  debugPrint(
                      "Unable to accept call from incoming call screen ${e.message}");
                });
            break;
          case Event.actionCallDecline:
            CometChatUIKitCalls.rejectCall(
                callEvent?.body["id"], CallStatusConstants.rejected,
                onSuccess: (Call call) {
                  call.category = MessageCategoryConstants.call;
                  CometChatCallEvents.ccCallRejected(call);
                  debugPrint('incoming call was cancelled');
                }, onError: (e) {
              debugPrint(
                  "Unable to end call from incoming call screen ${e.message}");
              debugPrint(
                  "Unable to end call from incoming call screen ${e.details}");
            });
            break;
          case Event.actionCallEnded:
            await FlutterCallkitIncoming.endCall(callEvent?.body['id']);
            break;
          default:
            break;
        }
      },
      cancelOnError: false,
      onDone: () {
        debugPrint('FlutterCallkitIncoming.onEvent: done');
      },
      onError: (e) {
        debugPrint('FlutterCallkitIncoming.onEvent:error ${e.toString()}');
      },
    );
  }
}