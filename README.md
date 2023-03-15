# Clairvoyant

Clairvoyant is a framework to provide monitoring data for Swift servers, targeted at [Vapor](https://vapor.codes). 
It enables the specification of different metrics to publish over a web API, where it can be collected by monitoring instances.

The framework can also be used as a logging backend for [swift-log](https://github.com/apple/swift-log), so that log contents can be made available conveniently over a web api (see [logging backend](#usage-with-swift-log)).

## Intention

This framework intends to provide a very lightweight logging and monitoring possibility, especially for Vapor servers. 
It allows publishing, collecting, and logging time-series data in a very simple way.
The goal is to provide easy remote access to basic information about running services, as well as provide history data.

It is maybe similiar to approaches like [swift-metrics](https://github.com/apple/swift-metrics), but without running a cumbersome monitoring backend.

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

```swift
let metric: Metric<Int> = Metric("myMetric")
```

Once a metric is created, it can be updated with new values:

```swift
metric.update(123)
```

The call to `update()` creates a timestamp for the given value, and persists this pair. 
Internally, metrics are only updated when the value changes, so calling `update()` multiple times with the same value does not unnecessarily increase the size of the log file.

It's also possible to get the last value or a history for each metric.

```swift
let last: Timestamped<Int>? = metric.lastValue()
```

The `Timestamped<T>` struct wraps a value with a timestamp to create a point in a time series.
That makes it possible to order values chronologically, and to obtain values within a specific interval.

```swift
let range = Date().addintTimeInterval(-100)...Date() // last 100 seconds
let lastValues: [Timestamped<Int>] = try metric.getHistory(in: range)
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
observer.log("Something happened")
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

## Exposing metrics with Vapor

Logging values to disk is great, but the data should also be available for inspection and monitoring.
Clairvoyant provides a separate module `ClairvoyantVapor` to integrate metric access into Vapor servers.
Each `MetricObserver` can be exposed separately on a subpath of the server.

```swift
import Clairvoyant
import ClairvoyantVapor

func configure(app: Application) {
    let observer = MetricObserver(...)
    let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())
    observer.registerRoutes(app)
}
```

This will add a number of routes to the default path, which is `/metrics`.
The path can also be passed as a parameter to `registerRoutes()`.

### Access control

A `VaporMetricProvider` requires an access manager, as seen in the example above.
Since the metrics may contain sensitive data, they should only be accessible by authorized entities.
Access control is left to the application, since there may be many ways to handle authentication and access control.
To manage access control, a `MetricRequestAccessManager` must be provided for each metric provider.

```swift
final class MyAuthenticator: MetricRequestAccessManager {

    func metricListAccess(isAllowedForRequest request: Request) throws {
        throw MetricError.accessDenied
    }

    func metricAccess(to metric: MetricId, isAllowedForRequest request: Request) throws {
        throw MetricError.accessDenied
    }
}
```

The authenticator must be provided to the initializer of a `VaporMetricProvider`.

```swift
let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())
```

If the authentication should be based on access tokens, it's also possible to implement `MetricAccessManager`.

```swift
final class MyAuthenticator: MetricAccessManager {
    
    func metricListAccess(isAllowedForToken accessToken: Data) throws {
        throw MetricError.accessDenied
    }

    func metricAccess(to metric: MetricId, isAllowedForToken accessToken: Data) throws {
        throw MetricError.accessDenied
    }
}
```

Or, if very basic authentication should be used, by using the provided in-memory stub:
```swift
let accessToken: Set<AccessToken> = ...
let authenticator = AccessTokenManager(accessToken)
let provider = VaporMetricProvider(observer: observer, accessManager: authenticator)
```

### API

Now that the metrics are protected, they can be accessed by authorized entities. 
There are currently four main entry points. 
All requests are `POST` requests, and require authentication. 
**Note**: If the included clients are used, then the API is already correctly implemented and not important. 

#### `/list`

Lists the metrics currently published by the observer.
The request calls the function `metricListAccess(isAllowedForRequest:)` or `metricListAccess(isAllowedForToken:)`, whichever is implemented.

The response is an array of `MetricDescription`, encoded with the binary encoder assigned to the `MetricObserver`.

#### `/last/<METRIC_ID_HASH>`

Get the last value of the metric. The `<METRIC_ID_HASH>` are the first 16 bytes of the SHA256 hash of the metric `ID` as a hex string (32 characters). Authentication of the request depends on the chosen implementation.

#### `/history/<METRIC_ID_HASH>`

Get the logged values of a metric in a specified time interval. The time interval is provided in the request body as a binary encoding of a `ClosedRange<Date>`. Authentication of the request depends on the chosen implementation.

### Pushing to other servers

**This feature is not implemented yet**

### Receiving from other servers

**This feature is not implemented yet**

### Complex types

**To Be Documented**

## Usage with `swift-log`

Clairvoyant can be used as a logging backend for `swift-log`, so that all logs are made available as `String` metrics.
To forward logs as metrics, first import the required module:

```swift
import Clairvoyant
import ClairvoyantLogging
```

Now, simply set an observer as the backend:

```swift
let observer = MetricObserver(...)
let logging = MetricsLogging(observer: observer)
LoggingSystem.bootstrap(logging.backend)
```

Each logging entry will then be timestamped and added to a metric with the same `ID` as the logger `label`.

```swift
let logger = Logger(label: "my.log")
logger.info("It works!")
```

The logging metrics are made available over the API in the same way as other metrics, and can also be accessed directly.

```swift
let metric = observer.getMetric(id: "my.log", type: String.self)
```

It's possible to change the logging format by setting the `loggingFormat` property on `MetricLogging` before creating a logger.
The property applies to each new logger, but changes are not propagated to existing ones.

```swift
logging.outputFormat = .full
```

## Usage with `swift-metrics`

Clairvoyant can be used as a metrics backend for [`swift-metrics`](https://github.com/apple/swift-metrics), to store metrics and serve them over a web api.
Each `Counter`, `Recorder`, `Gauge` or `Timer` is forwarded to a metric with the same `label` (`id`). While counters become `Metric<Int>`, all others become `Metric<Double>` (be aware of the unaccuracy of `Double` when using `Recorder.record(Int64)`).

To use a `MetricObserver` as a metrics backend, first import the module:

```swift
import Clairvoyant
import ClairvoyantMetrics
```

Then set the observer as the metrics backend:

```swift
let observer = MetricObserver(...)
let metrics = MetricsProvider(observer: observer)
MetricsSystem.bootstrap(metrics)
```

Now the metrics can be used, and are available through the web API or locally.

```swift
let counter = Counter(label: "com.example.BestExampleApp.numberOfRequests")
counter.increment()
```

To access the values locally:

```swift
let metric = observer.getMetric(id: "...", type: String.self)
let lastValue = await metric.lastValue()
```

## Initial requirements

- Allow publishing of individual metrics
- Allow different data types: Int, Bool, Double, Enum, and complex objects
- Use efficient binary encoding
- Specify read and write access for each property
- Protect information through access control
- Allow logging of changed values to disk
- Allow access to current value and optionally all past values
- Collect metrics from different sources: Variables, log files, online requests, etc.
- Provide information about the retrievable parameters
- General logging of errors
- Push changed values to different server

## Open tasks

- Allow changing the log file size
- Push updates to remote server
- Ensure completeness of log when pulling data from remote metrics
- Provide values as strings/JSON for web view
