/// 家长 PIN 凭据的最小系统边界。
///
/// 业务层只表达保存、验证、存在性和删除，不接触 Keychain 查询字典或凭据编码格式。
protocol ParentPINCredentialStoring {
    func containsCredential() throws -> Bool
    func store(_ pin: ParentPIN) throws
    func verify(_ pin: ParentPIN) throws -> Bool
    func removeCredential() throws
}
