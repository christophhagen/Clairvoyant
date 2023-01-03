# Clairvoyant

Clairvoyant is a framework to provide monitoring data for Swift servers, targeted at [Vapor](https://vapor.codes). 
It enables the specification of different metrics to publish over a web API, where it can be collected by monitoring instances.

**This repository is in early development**

Here are the initial requirements:
- Allow publishing of individual metrics
- Allow different data types: Int, Bool, Double, Enum, and complex objects
- Use efficient binary encoding
- Specify read and write access for each property
- Protect information through access control
- Allow logging of changed values to disk
- Allow access to current value and optionally all past values
- Collect metrics from different sources: Variables, log files, online requests, etc.
- Provide information about the retrievable parameters
