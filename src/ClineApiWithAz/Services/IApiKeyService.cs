using ClineApiWithAz.Models.Domain;

namespace ClineApiWithAz.Services;

public interface IApiKeyService
{
    /// <summary>APIキーを検証し、紐付くメンバーを返す。無効なキーの場合は null を返す。</summary>
    Task<Member?> ValidateAndGetMemberAsync(string rawApiKey);
}
