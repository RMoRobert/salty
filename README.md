# Salty
Salty is a recipe management app written in Swift, primarily using SwiftUI for the interface and SQLite, specifically GRDB via SharingGRDB, for persistence. The primary focus at the moment is macOS, with the intent of ensuring iOS/iPad OS compatibility in the future.

<!-- Some consideration is being given to an additional cross-platform viewer or even similarly-featured solution, perhaps using a tool such as .NET MAUI or Electron. However, there are no concrete plans for such at the moment. -->

Salty is currently **alpha-quality software** and use in a production environment is *not recommended*.

## Building and Targets

Saltly is typically built using the latest XCode on the latest macOS (excluding betas), current XCode 16 on macOS Sequoia (15). Compatibility with odler OS versions is not guaranteed, and seems unlikely given use of certain SwiftUI features, but may be revisited in the future.

# License

See [LICENSE](license).
