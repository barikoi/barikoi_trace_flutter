/// Connection state of the SDK's MQTT client.
///
/// **Reserved — not yet emitted in v1.** Neither native SDK exposes a
/// connection-state callback today, so no channel currently carries these
/// values. The enum is declared now so that adding an
/// `barikoi_trace_flutter/mqtt_state` event channel later is an additive
/// change for host apps rather than a new public type.
enum TraceMqttState {
  /// No connection, and none being attempted.
  disconnected,

  /// A CONNECT is in flight for the first time.
  connecting,

  /// CONNACK received; publishes are flowing.
  connected,

  /// The connection dropped and the client is retrying.
  reconnecting,

  /// The broker refused CONNECT (bad credentials, or an ACL that does not
  /// authorize the client id).
  rejected,
}
