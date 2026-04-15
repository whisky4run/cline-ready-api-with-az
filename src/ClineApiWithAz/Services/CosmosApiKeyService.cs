using System.Security.Cryptography;
using System.Text;
using ClineApiWithAz.Models.Domain;
using Microsoft.Azure.Cosmos;
using Microsoft.Azure.Cosmos.Linq;

namespace ClineApiWithAz.Services;

/// <summary>Cosmos DB を使用した APIキー検証サービス</summary>
public class CosmosApiKeyService(CosmosClient cosmosClient, IConfiguration configuration, ILogger<CosmosApiKeyService> logger) : IApiKeyService
{
    private readonly string _databaseName = configuration["CosmosDb:DatabaseName"] ?? "ClineApiDb";
    private readonly string _apiKeysContainer = "ApiKeys";
    private readonly string _membersContainer = "Members";

    public async Task<Member?> ValidateAndGetMemberAsync(string rawApiKey)
    {
        try
        {
            var keyHash = ComputeHash(rawApiKey);
            var database = cosmosClient.GetDatabase(_databaseName);
            var container = database.GetContainer(_apiKeysContainer);

            // ハッシュで一致する有効な APIキーを検索
            var query = container.GetItemLinqQueryable<ApiKey>()
                .Where(k => k.KeyHash == keyHash && k.IsActive)
                .ToFeedIterator();

            ApiKey? apiKey = null;
            while (query.HasMoreResults)
            {
                var page = await query.ReadNextAsync();
                apiKey = page.FirstOrDefault();
                if (apiKey is not null) break;
            }

            if (apiKey is null) return null;

            // メンバー情報を取得
            var membersContainer = database.GetContainer(_membersContainer);
            var memberResponse = await membersContainer.ReadItemAsync<Member>(
                apiKey.MemberId, new PartitionKey(apiKey.MemberId));
            var member = memberResponse.Resource;

            if (!member.IsActive) return null;

            // 最終使用日時を非同期で更新（失敗しても無視）
            _ = UpdateLastUsedAsync(container, apiKey);

            return member;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "APIキー検証中にエラーが発生しました");
            return null;
        }
    }

    private async Task UpdateLastUsedAsync(Container container, ApiKey apiKey)
    {
        try
        {
            var patch = new List<PatchOperation>
            {
                PatchOperation.Set("/lastUsedAt", DateTime.UtcNow)
            };
            await container.PatchItemAsync<ApiKey>(apiKey.Id, new PartitionKey(apiKey.MemberId), patch);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "APIキーの最終使用日時の更新に失敗しました: {KeyId}", apiKey.Id);
        }
    }

    private static string ComputeHash(string input)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(input));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }
}
