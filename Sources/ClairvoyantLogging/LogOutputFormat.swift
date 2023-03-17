import Foundation

/**
 The format to apply when converting log messages to strings.
 */
public enum LogOutputFormat: String {

    /**
     Adds the level, source, file info, and message.

     The format has the form `[LEVEL][SOURCE:FILE:FUNCTION:LINE] MESSAGE`
     */
    case full = "full"

    /**
     Add most data, except the source is omitted, and only the last path component of the file

     The format has the form `[LEVEL][FILE_NAME:FUNCTION:LINE] MESSAGE`
     */
    case medium = "origin"

    /**
     Only the log level and message are saved.

     The format has the form `[LEVEL] MESSAGE`
     */
    case basic = "level"

    /**
     Only the message is saved.
     */
    case message = "message"
}
