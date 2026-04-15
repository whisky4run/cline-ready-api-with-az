using ClineApiWithAz.Models.Domain;
using ClineApiWithAz.Models.Responses;
using Microsoft.Azure.Cosmos;
using Microsoft.Azure.Cosmos.Linq;

namespace ClineApiWithAz.Services;

/// <summary>Cosmos DB を使用した使用量記録・集計サービス</summary>
public class CosmosUsageService(CosmosClient cosmosClient, IConfiguration configuration, ILogger<CosmosUsageService> logger) : IUsageService
{
    private readonly string _databaseName = configuration["CosmosDb:DatabaseName"] ?? "ClineApiDb";
    private readonly string _usageContainer = "UsageRecords";
    private readonly string _membersContainer = "Members";

    public void RecordUsage(string memberId, string entraId, string model, int promptTokens, int completionTokens, long durationMs, int statusCode)
    {
        // fire-and-forget: 書き込み失敗はレスポンスに影響させない
        _ = RecordUsageInternalAsync(memberId, entraId, model, promptTokens, completionTokens, durationMs, statusCode);
    }

    private async Task RecordUsageInternalAsync(
        string memberId, string entraId, string model, int promptTokens, int completionTokens, long durationMs, int statusCode)
    {
        try
        {
            var record = new UsageRecord
            {
                MemberId = memberId,
                EntraId = entraId,
                Model = model,
                PromptTokens = promptTokens,
                CompletionTokens = completionTokens,
                TotalTokens = promptTokens + completionTokens,
                DurationMs = durationMs,
                StatusCode = statusCode,
                RequestedAt = DateTime.UtcNow
            };

            var container = cosmosClient.GetDatabase(_databaseName).GetContainer(_usageContainer);
            await container.CreateItemAsync(record, new PartitionKey(memberId));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "使用量レコードの書き込みに失敗しました: memberId={MemberId}", memberId);
        }
    }

    public async Task<UsageSummary> GetUsageSummaryAsync(string memberId, string memberName, string entraId, string email, DateTime from, DateTime to)
    {
        try
        {
            var container = cosmosClient.GetDatabase(_databaseName).GetContainer(_usageContainer);
            var query = container.GetItemLinqQueryable<UsageRecord>()
                .Where(r => r.MemberId == memberId && r.RequestedAt >= from && r.RequestedAt <= to)
                .ToFeedIterator();

            long promptTokens = 0, completionTokens = 0, count = 0;
            while (query.HasMoreResults)
            {
                var page = await query.ReadNextAsync();
                foreach (var record in page)
                {
                    promptTokens += record.PromptTokens;
                    completionTokens += record.CompletionTokens;
                    count++;
                }
            }

            return new UsageSummary
            {
                MemberId = memberId,
                MemberName = memberName,
                EntraId = entraId,
                Email = email,
                TotalPromptTokens = promptTokens,
                TotalCompletionTokens = completionTokens,
                TotalTokens = promptTokens + completionTokens,
                RequestCount = count
            };
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "使用量サマリーの取得に失敗しました: memberId={MemberId}", memberId);
            return new UsageSummary { MemberId = memberId, MemberName = memberName, EntraId = entraId, Email = email };
        }
    }

    public async Task<List<UsageSummary>> GetAllUsageSummariesAsync(DateTime from, DateTime to, string? memberId = null)
    {
        try
        {
            var database = cosmosClient.GetDatabase(_databaseName);
            var usageContainer = database.GetContainer(_usageContainer);
            var membersContainer = database.GetContainer(_membersContainer);

            // 全メンバーを取得
            var membersQuery = membersContainer.GetItemLinqQueryable<Member>()
                .Where(m => m.IsActive)
                .ToFeedIterator();

            var members = new List<Member>();
            while (membersQuery.HasMoreResults)
            {
                var page = await membersQuery.ReadNextAsync();
                members.AddRange(page);
            }

            if (memberId is not null)
                members = members.Where(m => m.Id == memberId).ToList();

            // 各メンバーの使用量を集計
            var summaries = new List<UsageSummary>();
            foreach (var member in members)
            {
                var summary = await GetUsageSummaryAsync(member.Id, member.Name, member.EntraId, member.Email, from, to);
                summaries.Add(summary);
            }

            return summaries;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "全使用量サマリーの取得に失敗しました");
            return [];
        }
    }
}
