# Clairvoyant

Clairvoyant is a framework to provide monitoring data for Swift servers, targeted at [Vapor](https://vapor.codes). 
It enables the specification of different metrics to publish over a web API, where it can be collected by monitoring instances.

**This repository is in early development**

## Intention

This framework intends to provide a very lightweight logging and monitoring possibility for Vapor servers. 
It allows publishing, collecting, and logging time-series data in a very simple way.
The goal is to provide easy remote access to basic information about running services, as well as provide history data.

It is maybe similiar to approaches like [swift-metrics](https://github.com/apple/swift-metrics), but without running a cumbersome momnitoring backend.

## Usage

Clairvoyant is structured around the concept of `metrics`, which are monitored by `observers`. 
A metric describes a basic data point over time, such as integers, doubles, enums, or other data types. 
A metric collects any changes to the data point, logs it to disk, and optionally forwards the data to a remote server.
Metrics are identified by a unique identifier string.

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
Internally, metrics are only updated when the value changes, so calling `update()` multiple times with the same value does not unecessarily increase the size of the log file.

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
The observer is responsible for writing new data to disk, and providing Vapor routes to access the data.
Managing access to the metrics is done by a [`MetricAccessManager`](#access-control), which we'll focus on later.
To create an observer, we have to provide a directory where the logging data can be written.
It also internally writes all errors to a `Metric<String>` with the `id` provided by the parameter `logMetricId`.

```swift
let url: URL = ...
let observer = MetricObserver(
        logFolder: url, 
        authenticator: MyAuthenticator(), 
        logMetricId: "test.log")
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

There is also a static property on `MetricObserver` to add metrics to by default:

```swift
MetricObserver.standard = observer
let metric = Metric("metric", containing: Int.self) // Automatically added to `observer`
```

### Exposing metrics

Logging values to disk is great, but the data should also be available for inspection and monitoring.
This is done by adding routes to the Vapor server, where the metrics can be requested from external clients.
This can be done e.g. in the `configure()` function of the Vapor instance.

```swift
func configure(app: Application) {
    let observer = MetricObserver(...)
    observer.registerRoutes(app, subPath: "metrics")
}
```

This will add a number of routes to the default path, which is `/metrics`.

### Access control

Since the metrics may contain sensitive data, they should only be accessible by authorized entities.
Access control is left to the application, since there may be many ways to handle authentication and access control.
To manage access control, a `MetricRequestAccessManager` must be provided.

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

The authenticator must be provided to the initializer of a `MetricObserver`.

```swift
let observer = MetricObserver(
        logFolder: url, 
        authenticator: MyAuthenticator(), 
        logMetricId: "test.log")
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
let observer = MetricObserver(logFolder: url, authenticator: authenticator, logMetricId: "test.log")
```

### API

Now that the metrics are protected, they can be accessed by authorized entities. 
There are currently four main entry points. 
All requests are `POST` requests, and require authentication. 

#### `/list`

Lists the metrics currently published by the observer.
The request calls the function `metricListAccess(isAllowedForRequest:)` or `metricListAccess(isAllowedForToken:)`, whichever is implemented.

The response is an array of `MetricDescription`, encoded with the binary encoder assigned to the `MetricObserver`.

#### `/last/<METRIC_ID>`

Get the last value of the metric.

### Pushing to other servers

**This feature is not implemented yet**

### Receiving from other servers

**This feature is not implemented yet**

### Complex types

**To Be Documented**

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
- Push updates to remote server
- Ensure completeness of log when pulling data from remote metrics
- Split logs if files get too big
- Provide values as strings/JSON for web view
