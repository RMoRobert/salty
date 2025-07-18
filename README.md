# Salty
Salty is a recipe management app for macOS, iOS, and iPadOS. Salty works on macOS and iOS (iPhone and iPad). This app was born out of a desire to substantially replace my longstanding use of the MacGourmet Deluxe application on Mac, as the company behind it app seems to have vanished, and some problems with the apparently abandoned application are becoming apparent. Salty is *not* a clone but rather a modern re-thinking of recipe management for macOS. I have tried several alternatives, but found them uninspriring or mobile-focused and difficult to use on desktop. Salty aims to work well on macOS while also offering mobile compatibility without compromising the desktop experience.

If you are an end user, Salty is currently **alpha-quality software** and use in a production environment is *not recommended*. I have written it for my personal use, shared it as-is, and plan to continue development as my time allows.

Give my history with MacGourmet and my desire to import as much recipe data as possible, many features (and fields on recipe entries) mirror those of MacGourmet. Some less commonly used features (equipment, etc.) and fields are not currently implemented and may never be, and not all fields will match up with the exact same names (e.g., keywords in MacGourmet will be attempted to be split and parsed into "tags" in Salty). Further, some data is simply apparently not present in any MacGourmet export and therefore cannot be imported, most notably, star ratings.

## Technical Details 

Salty is written in Swift, making primary use of SwiftUI for the interface and GRDB (via SharingGRDB) for persistence, ultimately making use of SQLite.

### Building and Targets

Saltly is typically built using the latest XCode on the latest macOS (excluding betas), currently XCode 16.4 on macOS Sequoia (15.x). We have tested only on macOS 15 and iOS 18; compatibility with older versions is not a priority at this moment (but we will aim for forwards-compatibility).

# License

See [LICENSE](license).
