# Salty
Salty is a recipe management app written in Swift, primarily using SwiftUI for the interface and Realm for persistence. The primary focus at the moment is macOS, with efforts made to ensure iOS and iPadOS parity for as many features as possible (but priority is given to macOS for the time being).

<!-- Some consideration is being given to an additional cross-platform viewer or even similarly-featured solution, perhaps using a tool such as .NET MAUI or Electron. However, there are no concrete plans for such at the moment. -->

Salty is currently **alpha-quality software** and use in a production environment is *not recommended*.

## Building and Targets

Saltly is typically built using the latest XCode 14 release on macOS Ventura (13.x) release targeting recent releases of macOS Ventura (13) and iOS/iPadOS 16. Older versions are generally untested but unlikely to work due to SwiftUI features introduced in these versions.

# License

See [LICENSE](license).