Pod::Spec.new do |s|
  s.name = 'MukshatOrganic'
  s.version = '1.0.0'
  s.summary = 'Organic Maps engine bridge for the Mukshat Flutter prototype'
  s.homepage = 'https://github.com/mukshatapp/mikshat-ios'
  s.license = { :type => 'Apache-2.0', :file => '../../vendor/organicmaps/LICENSES/Apache-2.0.txt' }
  s.author = { 'Mukshat' => 'development@mukshat.local' }
  s.source = { :path => '.' }
  s.platform = :ios, '15.0'
  s.source_files = 'Classes/**/*.{h,hpp,mm}'
  s.public_header_files = 'Classes/MKOrganicPlugin.h'
  s.dependency 'Flutter'
  s.vendored_libraries = 'Artifacts/libMukshatCore.a'
  s.resources = ['Artifacts/MukshatData.bundle', 'Artifacts/default.metallib']
  s.frameworks = 'UIKit', 'Foundation', 'CoreLocation', 'Metal', 'MetalKit', 'QuartzCore', 'CoreGraphics', 'SystemConfiguration', 'Security', 'CFNetwork', 'Network', 'OpenGLES', 'CoreText', 'ImageIO'
  s.libraries = 'c++', 'z', 'bz2', 'sqlite3', 'icucore'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++23',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) OMIM_METAL_AVAILABLE=1 RELEASE=1',
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Engine/libs" "$(PODS_TARGET_SRCROOT)/Engine/3party" "$(PODS_TARGET_SRCROOT)/Engine/3party/boost" "$(PODS_TARGET_SRCROOT)/Engine/3party/glm" "$(PODS_TARGET_SRCROOT)/Engine/3party/glaze/include" "$(PODS_TARGET_SRCROOT)/Engine/3party/pugixml/pugixml/src" "$(PODS_TARGET_SRCROOT)/Engine/3party/jansson/src" "$(PODS_TARGET_SRCROOT)/Engine/3party/utfcpp/source"'
  }
end
