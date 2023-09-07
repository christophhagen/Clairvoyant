<p align="center">
    <img src="assets/banner.png" width="500" max-width="90%" alt="Clairvoyant" />
</p>

Clairvoyant is a framework to provide monitoring data for Swift servers, targeted at [Vapor](https://vapor.codes). 
It enables the specification of different metrics to publish over a web API, where it can be collected by monitoring instances.

The framework can also be used as a logging backend for [swift-log](https://github.com/apple/swift-log), so that log contents can be made available conveniently over a web api (see [logging backend](#usage-with-swift-log)).

## Intention

This framework intends to provide a very lightweight logging and monitoring possibility, especially for Vapor servers. 
It allows publishing, collecting, and logging time-series data in a very simple way.
The goal is to provide easy remote access to basic information about running services, as well as provide history data.

It is maybe similiar to approaches like [swift-metrics](https://github.com/apple/swift-metrics), but without running a cumbersome monitoring backend, and with a bit more flexibility.

### Packages

This package is part of a larger collection of Swift packages, which separate the logic according to the needed functions.

| Module | Content |
| --- | --- |
| Clairvoyant | The main module with metrics and consumers |
| [ClairvoyantVapor](https://github.com/christophhagen/ClairvoyantVapor) | Extensions to expose metrics through a [Vapor](https://vapor.codes) server |
| [ClairvoyantClient](https://github.com/christophhagen/ClairvoyantClient) | A client to communicate with a [ClairvoyantVapor](https://github.com/christophhagen/ClairvoyantVapor) server |
| [ClairvoyantLogging](https://github.com/christophhagen/ClairvoyantLogging) | Use a metrics observer as a backend for [swift-log](https://github.com/apple/swift-log) |
| [ClairvoyantMetrics](https://github.com/christophhagen/ClairvoyantMetrics) | Use a metrics observer as a backend for [swift-metrics](https://github.com/apple/swift-metrics) |
| [ClairvoyantCBOR](https://github.com/christophhagen/ClairvoyantCBOR) | Extensions to use [CBOR](https://cbor.io) encoding for metrics |
| [ClairvoyantBinaryCodable](https://github.com/christophhagen/ClairvoyantBinaryCodable) | Extensions to use [BinaryCodable](https://github.com/christophhagen/BinaryCodable) encoding for metrics |

The individual packages are explained in more detail below.

## Usage

Clairvoyant is structured around the concept of `metrics`, which are monitored by `observers`. 
A metric describes a basic data point over time, such as integers, doubles, enums, or other data types. 
A metric collects any changes to the data point, logs it to disk, and optionally forwards the data to a remote server.
Metrics are identified by a unique identifier string.

```swift
import Clairvoyant
```

### Metrics

Let's first create a metric before discussing logging and access control.
Metrics are written as Swift `Actor`s, so they are thread-safe, but require an asynchronous context.

```swift
let metric: Metric<Int> = try await Metric("myMetric")
```

Once a metric is created, it can be updated with new values:

```swift
try await metric.update(123)
```

The call to `update()` creates a timestamp for the given value, and persists this pair. 
Internally, metrics are only updated when the value changes, so calling `update()` multiple times with the same value does not unnecessarily increase the size of the log file.
Datapoints older than the last value are also ignored (only applicable when setting custom timestamps).

It's also possible to get the last value or a history for each metric.

```swift
let last: Timestamped<Int>? = await metric.lastValue()
```

The `Timestamped<T>` struct wraps a value with a timestamp to create a point in a time series.
That makes it possible to order values chronologically, and to obtain values within a specific interval.

```swift
let range = Date().addintTimeInterval(-100)...Date() // last 100 seconds
let lastValues: [Timestamped<Int>] = try await metric.getHistory(in: range)
```

These functions represent the basic interaction with a metric on the creator side.

### Metric observer

A `Metric` requires a `MetricObserver` to receive the data and process it.
The observer is responsible for managing different metrics, and provide a common storage location.
To create an observer, we have to provide a directory where the logging data can be written.
It also internally writes all errors to a `Metric<String>` with the `id` provided by the parameter `logMetricId`.

```swift
let url: URL = ...
let observer = MetricObserver(logFolder: url, logMetricId: "test.log")
```

The logging metric can later be read in the same way as other metrics.
It's also possible to add additional log entries.

```swift
await observer.log("Something happened")
```

The observer is now ready to handle metrics, so the previously created metric can be added to it.

```swift
observer.observe(metric)
```

It's also possible to directly create metrics on the observer:
```swift
let metric: Metric<Int> = observer.addMetric("MyCounter")
```

There is a static property on `MetricObserver` to add metrics to by default:

```swift
MetricObserver.standard = observer
let metric = Metric("metric", containing: Int.self) // Automatically added to `observer`
```

### Complex types

It's possible to use metrics with custom types, so that arbitrary data can be logged.
Any complex type that conforms to the `MetricValue` protocol works.
The protocol requirements are a static property of `MetricType`, an `Enum` to signal the type of data being encoded.
Custom types should use the `.customType(named:)` case.

Additionally, custom types must conform to `Codable` (for encoding/decoding) and `Equatable`, to allow comparisons with the last value.

```swift
struct Player: MetricValue, CustomStringConvertible {

    static let valueType: MetricType = .custom(named: "Player")
    
    let name: String
    
    let score: Int
    
    var description: String { "\(name) (\(score))"}
}
```

This is already sufficient to use metrics with the type, like so:

```swift
let metric = Metric("player.current", containing: Player.self)
let newPlayer = Player(name: "Alice", score: 42)
try await metric.update(newPlayer)
```

On the client side, this process works in much the same way, by creating a `ConsumableMetric` of the custom type.

```swift
let myMetric: ConsumableMetric<Player> = metricConsumer.metric(id: "player.current")
```

One special addition should be made when using `GenericConsumableMetric`s to use metrics in type-erased ways, e.g. in SwiftUI views.
It's not possible for a `MetricConsumer` to decode custom types without knowing about the type, so each custom type used in generic metrics should be registered with the consumer:

```swift
metricConsumer.register(customType: Player.self, named: "Player")
```

Now, textual descriptions of the generic metric gives useful output:

```swift
let genericMetric = myMetric as GenericConsumableMetric
let description = try await genericMetric.lastValueDescription()!.value
print(description) // Prints "Alice (42)"
```

### Exposing metrics with Vapor

Logging values to disk is great, but the data should also be available for inspection and monitoring.
Clairvoyant provides a separate package [ClairvoyantVapor](https://github.com/christophhagen/ClairvoyantVapor) to integrate metric access into Vapor servers.

### Receiving from other servers

To receive a metric pushed from a remote server, configure a metric with `canBeUpdatedByRemote = true`. Any time a new value is received the metric will be updated with this value.
The last value as well as history data can be accessed as with any other metric.

### Pushing to other servers

Metrics can be configured to automatically transmit the logged values to a remote server for monitoring or persistence.
To configure this feature, one or more `RemoteMetricObserver`s can be added to each metric.
Whenever a new value is set, then the metric attempts to send all pending updates (including any previously failed values) to the remote observer using the `push` route specified above.

The remote server must have a metric with the same `id` registered with the observer, and the metric must be configured with `canBeUpdatedByRemote = true`.

## Initial requirements

**Allow publishing of individual metrics** *Implemented*

Different metrics can be created, updated, and exposed through a Vapor server.

**Allow different data types: Int, Bool, Double, Enum, and complex objects** *Implemented*

Any Swift type can be used as a metric, as long as it conforms to `MetricValue`. 
Some standard types have been implemented: `Int`, `Double`, `Bool`, `Enum(UInt8)`, and `ServerStatus`.

**Use efficient binary encoding** *Implemented*

Any binary encoder can be specified for encoding and decoding, as long as it conforms to `BinaryEncoder` and `BinaryDecoder`.
The native types for JSON (`JSONEncoder` and `JSONDecoder`) and Property Lists (`PropertyListEncoder` and `PropertyListDecoder`) work out of the box.
There are additional packages which can be included for more efficient binary encoders:

To use [CBOR](http://cbor.io), include the [ClairvoyantCBOR](https://github.com/christophhagen.de/ClairvoyantCBOR) package.
To use [BinaryCodable](https://github.com/christophhagen.de/BinaryCodable), include [ClairvoyantBinaryCodable](https://github.com/christophhagen.de/ClairvoyantBinaryCodable).

**Specify read and write access for each property** *Implemented*

Access control is left to the application, and can be performed individually for each request.
Some convenience functions are provided to simplify access control through tokens.

**Protect information through access control** *Implemented*

See above.

**Allow logging of changed values to disk** *Implemented*

Values are timestamped and written to log files on disk. 
Log files are split according to a configurable maximum size.

**Allow access to current value and optionally all past values** *Implemented*

Metrics provide `lastValue()` and `getHistory()` functions to access stored values.
These can also be accessed through the Vapor web interface.

**Collect metrics from different sources: Variables, log files, online requests, etc.** *Not implemented*

Feeding metric with values is left to the application.
Additional features may be implemented in time to observe and process log files or perform automatic requests.
 
**Provide information about the retrievable parameters** *Implemented*

`MetricObservers` provide a list of the metrics with basic information (name, description, type) about them.

**General logging of errors** *Implemented*

Each `MetricObserver` has a metric dedicated to logging of internal errors

**Push changed values to different server** *Implemented*

Metrics can be configured with remote observers, were new values are automatically transmitted to.

## Open tasks

- Persist pending values to remote observers between launches
- Add total file size limit to metric (automatically delete oldest files)
- Provide values as strings/JSON for web view
- Add convenience features to observe log files or perform periodic network requests.
- Provide functionality to fully synchronize metrics across systems
