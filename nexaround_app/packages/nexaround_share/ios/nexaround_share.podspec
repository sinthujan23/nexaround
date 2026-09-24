# Used only when a build has Swift Package Manager turned off; the CI build
# uses Package.swift. Keep the Facebook SDK major version in step with
# facebook_app_events.
Pod::Spec.new do |s|
  s.name             = 'nexaround_share'
  s.version          = '0.0.1'
  s.summary          = 'Direct Facebook and Instagram Stories sharing for nexARound.'
  s.homepage         = 'https://nexaround.com'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'nexARound' => 'dev@nexaround.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'nexaround_share/Sources/nexaround_share/**/*.swift'
  s.static_framework = true
  s.dependency 'Flutter'
  s.dependency 'FBSDKShareKit', '~> 18.0'
  s.ios.deployment_target = '14.0'
  s.swift_version    = '5.9'
end
