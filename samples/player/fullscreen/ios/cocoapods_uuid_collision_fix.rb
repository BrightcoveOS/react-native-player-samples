# Fixes a UUID collision in CocoaPods' predictable-UUID generator that
# corrupts Pods.xcodeproj when React Native's SPM hook adds the Brightcove
# SDK package reference.
#
# Pod::Project#generate_available_uuid_list produces sequential UUIDs
# (<6-char prefix><counter>) tracked only by the in-memory @generated_uuids
# array. When a post_install hook creates a new object on a project instance
# whose counter state does not cover the objects already in the project
# (e.g. react_native_pods' spm.rb adding an XCRemoteSwiftPackageReference),
# the counter restarts at 0 and hands out the root object's UUID
# (…00000000) again. Unlike Xcodeproj::Project's base implementation,
# CocoaPods' override never checks existing object UUIDs, so the duplicate
# silently overwrites the PBXProject entry when the pbxproj is serialized,
# and Xcode reports "The project 'Pods' is damaged".
#
# The fix mirrors the base implementation: skip candidate UUIDs that are
# already used by existing objects, while still advancing the counter.
require 'cocoapods'

module Pod
  class Project
    def generate_available_uuid_list(count = 100)
      start = @generated_uuids.size
      candidates = Array.new(count) { |i| format('%.6s%07X0', @uuid_prefix, start + i) }
      @generated_uuids += candidates
      @available_uuids += candidates - uuids
    end
  end
end
