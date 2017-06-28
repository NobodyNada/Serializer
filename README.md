# Serializer

[![Build Status](https://travis-ci.org/NobodyNada/Serializer.svg?branch=master)](https://travis-ci.org/NobodyNada/Serializer)

Swift 4's new `Codable` protocol makes it much simpler to serialize Swift objects.  The built-in [`JSONEncoder`](https://github.com/apple/swift/blob/master/stdlib/public/SDK/Foundation/JSONEncoder.swift) and [`PlistEncoder`](https://github.com/apple/swift/blob/master/stdlib/public/SDK/Foundation/PlistEncoder.swift) encode and decode JSON and plist, but what about when you need to use other formats?

Writing a custom encoder is fairly complex, so Serializer takes care of that for you.  Serializer converts your Swift objects into a simple `enum`, which you can easily traverse and write to a file format of your choice.

All you have to do is implement the `Serializer` protocol and create a method called `serialize`, which encodes a `Serializable` enum into your custom format.  Decoding is similar -- add the `Deserializer` protocol, with a `deserialize` method which converts your custom format into a `Serializable`.  [Here's an example serializer and deserializer](https://gist.github.com/NobodyNada/ae18ca7e11ea432e10243d173cc13351) for the [NBT file format](http://wiki.vg/NBT)
