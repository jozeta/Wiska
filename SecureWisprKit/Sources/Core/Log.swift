import os

public enum Log {
    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: "SecureWispr", category: category)
    }
}
