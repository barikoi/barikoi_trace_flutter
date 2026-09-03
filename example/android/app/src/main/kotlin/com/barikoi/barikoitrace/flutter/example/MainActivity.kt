package com.barikoi.barikoitrace.flutter.example

import io.flutter.embedding.android.FlutterActivity

/**
 * Nothing to override.
 *
 * The plugin is `ActivityAware`, so it picks this Activity up automatically and
 * uses it for the permission prompts and the settings screens. The permission
 * results are delivered through the plugin's own
 * `PluginRegistry.RequestPermissionsResultListener`, which `FlutterActivity`
 * forwards to — so a host app never has to override
 * `onRequestPermissionsResult` itself.
 */
class MainActivity : FlutterActivity()
