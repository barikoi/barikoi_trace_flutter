/// Flutter bindings for the Barikoi Trace location-tracking SDKs.
///
/// Start from `BarikoiTrace` — everything else in this library is a model type
/// it takes or returns.
library;

export 'src/barikoi_trace.dart' show BarikoiTrace;
export 'src/method_channel/method_channel_barikoi_trace.dart'
    show MethodChannelBarikoiTrace;
export 'src/models/trace_config.dart' show TraceConfig;
export 'src/models/trace_exception.dart' show TraceErrorCode, TraceException;
export 'src/models/trace_location.dart' show TraceLocation;
export 'src/models/trace_log_entry.dart' show TraceLogEntry;
export 'src/models/trace_mode.dart'
    show
        DesiredAccuracy,
        TraceMode,
        TraceModeBuilder,
        TraceTimeOfDay,
        TrackingMode;
export 'src/models/trace_mqtt_state.dart' show TraceMqttState;
export 'src/models/trace_user.dart' show TraceUser;
export 'src/platform_interface/barikoi_trace_platform.dart'
    show BarikoiTracePlatform;
export 'src/platform_specific/android_api.dart' show BarikoiTraceAndroid;
export 'src/platform_specific/ios_api.dart' show BarikoiTraceIos;
