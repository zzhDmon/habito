import Security

/// Keychain 凭据损坏或系统安全服务异常。
enum KeychainParentPINError: Error {
    case invalidCredential
    case unexpectedStatus(OSStatus)
}
