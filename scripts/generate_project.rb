#!/usr/bin/env ruby
require 'xcodeproj'
require 'fileutils'
root = File.expand_path('..', __dir__)
path = File.join(root, 'share_xuan.xcodeproj')
FileUtils.rm_rf(path) if File.exist?(path)
project = Xcodeproj::Project.new(path)
config = project.main_group.new_file('Config.xcconfig')
app = project.new_target(:application, 'share_xuan', :ios, '16.0')
extension = project.new_target(:app_extension, 'ShareExtension', :ios, '16.0')
[app, extension].each do |target|
  target.build_configurations.each do |build|
    build.base_configuration_reference = config
    build.build_settings.merge!({
      'SWIFT_VERSION' => '5.0', 'TARGETED_DEVICE_FAMILY' => '1,2',
      'GENERATE_INFOPLIST_FILE' => 'NO', 'CODE_SIGN_STYLE' => 'Automatic',
      'VERSIONING_SYSTEM' => 'apple-generic', 'CURRENT_PROJECT_VERSION' => '1',
      'MARKETING_VERSION' => '1.0.0', 'SWIFT_STRICT_CONCURRENCY' => 'minimal',
      'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES'
    })
  end
end
app.build_configurations.each do |build|
  build.build_settings.merge!({'PRODUCT_BUNDLE_IDENTIFIER' => '$(APP_BUNDLE_IDENTIFIER)', 'INFOPLIST_FILE' => 'App/Info.plist', 'CODE_SIGN_ENTITLEMENTS' => 'App/App.entitlements', 'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon'})
end
extension.build_configurations.each do |build|
  build.build_settings.merge!({'PRODUCT_BUNDLE_IDENTIFIER' => '$(SHARE_BUNDLE_IDENTIFIER)', 'INFOPLIST_FILE' => 'ShareExtension/Info.plist', 'CODE_SIGN_ENTITLEMENTS' => 'ShareExtension/ShareExtension.entitlements', 'APPLICATION_EXTENSION_API_ONLY' => 'YES', 'SKIP_INSTALL' => 'YES'})
end
{'App' => [app], 'ShareExtension' => [extension], 'Shared' => [app, extension]}.each do |directory, targets|
  group = project.main_group.new_group(directory, directory)
  Dir.glob(File.join(root, directory, '*')).sort.each do |file|
    ref = group.new_file(File.basename(file))
    targets.each { |target| target.source_build_phase.add_file_reference(ref) } if file.end_with?('.swift')
    targets.each { |target| target.resources_build_phase.add_file_reference(ref) } if file.end_with?('.xcassets')
  end
end
package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
package.relative_path = 'TransferCore'
project.root_object.package_references << package
product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product.product_name = 'TransferCore'
product.package = package
app.package_product_dependencies << product
build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = product
app.frameworks_build_phase.files << build_file
app.add_dependency(extension)
embed = app.new_copy_files_build_phase('Embed App Extensions')
embed.dst_subfolder_spec = '13'
embed.add_file_reference(extension.product_reference).settings = {'ATTRIBUTES' => ['RemoveHeadersOnCopy']}
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.save_as(path, 'share_xuan', true)
puts path
