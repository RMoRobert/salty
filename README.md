# Salty
Salty is a recipe management app for macOS, iOS, and iPadOS. Salty works on macOS and iOS (iPhone and iPad). This app was born out of a desire to substantially replace my longstanding use of the MacGourmet Deluxe application on Mac, as the company behind it app seems to have vanished, and some problems with the apparently abandoned application are becoming apparent. Salty is *not* a clone but rather a modern re-thinking of recipe management for macOS. I have tried several alternatives, but found them uninspriring or mobile-focused and difficult to use on desktop. Salty aims to work well on macOS while also offering mobile compatibility without compromising the desktop experience.

If you are an end user, I would consider Salty beta-quality software, although I am not aware of any major problems. I have written it for my personal use, shared it as-is, and plan to continue development as my time allows. (There are )

Given my history with MacGourmet and my desire to import as much recipe data as possible, many features (and fields on recipe entries) mirror those of MacGourmet. Some less commonly used features (equipment, etc.) and fields are not currently implemented and may never be, and not all fields will match up with the exact same names (e.g., keywords in MacGourmet will be attempted to be split and parsed into "tags" in Salty). Further, some data is simply apparently not present in any MacGourmet export and therefore cannot be imported -- most notably, star ratings.

## Local-First

Salty is a *local first* recipe manager: the database is, by default, created and stored on-device. (On macOS, find it inside the folder labeled "Salty" inside your ~/Library/Containers folder, as by default for all sandboxed apps; on iOS, data is by default similarly stored in your application's container, though it is not really user-accessible.) The app's Settings window allows changing to a custom location. This works well on macOS; on iOS, it seems to occasionally require re-selecting to re-gain access. You may use your own cloud storage provider to sync between devices if necessary (though again, particularly on iOS, this is more difficult). Exercise caution, depending on your provider -- do not access the database simultaneously from multiple devices. We will look into more straightforward cloud sync options in the future, perhaps including iCloud sync, but wanted to focus on traditional local storage first.

# Technical Details 

Salty is written in Swift, making primary use of SwiftUI for the interface and GRDB (via SQLiteData) for persistence, ultimately making use of SQLite. There is currently minimal unit testing, which would be a good improvement to add to the code in the future.

### Building and Targets

Saltly is typically built using the latest XCode on the latest or nearly latest macOS (excluding betas), currently XCode 26 on macOS Sequoia (15) or Tahoe (26). Salty should run and build on, at least, macOS 15 or 26 and iOS 18 or 26.

# License

See [LICENSE](license).
