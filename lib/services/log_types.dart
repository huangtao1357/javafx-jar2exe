enum LogLevel { command, info, success, warning, error }

typedef LogSink = void Function(String line, LogLevel level);
