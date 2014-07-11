# Shipit-iOS

Ruby gem for building iOS apps and uploading them to iTunes Connect right from the command line.

## Installation

Add this line to your application's Gemfile:

    gem 'shipit-ios'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install shipit-ios

## Usage

Usage is simple:

    $ shipit-ios --workspace MyCoolApp.xcworkspace --scheme MyCoolApp --configuration Release --upload

You will have a chance to modify the `BundleIdentifier` and `BundleShortVersionString`, as well as bump the build number, before the app is compiled.

If you don't already have your iTunes Connect credentials in your keychain, you will be prompted for them.

Make sure your app is 'Waiting for upload' in iTunes connect before running `--upload`.

`--archive` will copy the `.xcarchive` from `~/Library/Developer/Xcode/Archives/` into the working directory for easy access.

## Contributing

1. Fork it ( http://github.com/j-mutter/shipit-ios/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
