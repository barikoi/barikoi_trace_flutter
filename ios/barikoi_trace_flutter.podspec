#
# CocoaPods spec for the iOS side of `barikoi_trace_flutter`.
# Run `pod lib lint barikoi_trace_flutter.podspec` to validate before publishing.
#
# ---------------------------------------------------------------------------
# IMPORTANT — the `BarikoiTrace` dependency below needs a published podspec.
# ---------------------------------------------------------------------------
#
# The BarikoiTrace iOS SDK (https://github.com/barikoi/BarikoiTrace-ios-sdk)
# ships as a **Swift Package only**: its repository contains a `Package.swift`
# and no `BarikoiTrace.podspec`, and nothing is published to the CocoaPods
# trunk. So `s.dependency 'BarikoiTrace', '0.4.0'` cannot resolve out of the
# box — `pod install` will fail with "Unable to find a specification for
# `BarikoiTrace`".
#
# There are two ways forward, in order of preference:
#
#   1. Use Swift Package Manager. Flutter 3.24+ can build plugins with SPM
#      (`flutter config --enable-swift-package-manager`), and it is on by
#      default from Flutter 3.44. That path uses `barikoi_trace_flutter/Package.swift`
#      next to this file, which declares the SDK dependency properly and needs
#      no CocoaPods at all. This is the supported configuration.
#
#   2. Stay on CocoaPods. That requires a `BarikoiTrace.podspec` to exist for
#      the iOS SDK — either published to the trunk (`pod trunk push`) or added
#      to the repository. Until it is, the host app can point at one directly
#      from its own `ios/Podfile`, which takes precedence over the dependency
#      declared here:
#
#          # ios/Podfile
#          target 'Runner' do
#            use_frameworks!
#            pod 'BarikoiTrace',
#                :podspec => 'https://raw.githubusercontent.com/barikoi/BarikoiTrace-ios-sdk/0.4.0/BarikoiTrace.podspec'
#            # …or from a local checkout / fork:
#            # pod 'BarikoiTrace', :podspec => '../../BarikoiTrace-ios-sdk/BarikoiTrace.podspec'
#            flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
#          end
#
#      Note that such a podspec must also carry the SDK's own dependency on
#      CocoaMQTT (`s.dependency 'CocoaMQTT', '~> 2.1.6'`) and link `libsqlite3`,
#      since `Package.swift` declares both and a podspec does not inherit them.
#
Pod::Spec.new do |s|
  s.name             = 'barikoi_trace_flutter'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin for the Barikoi Trace location-tracking SDK (iOS).'
  s.description      = <<-DESC
Bridges the BarikoiTrace iOS SDK to Flutter: one method channel
(barikoi_trace_flutter/methods) plus event channels for live location fixes
and for the SDK's internal debug log.
                       DESC
  s.homepage         = 'https://github.com/barikoi/BarikoiTrace-flutter-plugin'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Barikoi' => 'dev@barikoi.com' }
  s.source           = { :path => '.' }

  # The sources live in the Swift Package layout so that one copy serves both
  # build systems. `flutter build ios` with CocoaPods compiles exactly these
  # files; with SPM, `barikoi_trace_flutter/Package.swift` does.
  s.source_files     = 'barikoi_trace_flutter/Sources/barikoi_trace_flutter/**/*.swift'

  # Privacy manifest. CocoaPods will not pick up a resource that is not
  # declared, and Apple requires it to ship inside the framework's own bundle.
  s.resource_bundles = {
    'barikoi_trace_flutter_privacy' => [
      'barikoi_trace_flutter/Sources/barikoi_trace_flutter/PrivacyInfo.xcprivacy'
    ]
  }

  s.dependency 'Flutter'
  s.dependency 'BarikoiTrace', '0.4.0'

  s.platform          = :ios, '15.0'
  s.ios.deployment_target = '15.0'
  s.swift_version     = '5.9'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Flutter.framework does not contain an i386 slice.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }

  # `ios/Assets/` is reserved for bundled resources and is deliberately not
  # globbed here: an empty resource bundle makes `pod lib lint` fail. Add a
  # `s.resource_bundles` entry for it at the same time as the first real asset.
end
