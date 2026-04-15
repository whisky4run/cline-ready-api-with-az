using ClineApiWithAz.Models.Responses;

namespace ClineApiWithAz.Services;

public interface IUsageService
{
    /// <summary>使用量レコードを記録する（fire-and-forget）</summary>
    void RecordUsage(string memberId, string entraId, string model, int promptTokens, int completionTokens, long durationMs, int statusCode);

    /// <summary>指定メンバーの使用量サマリーを取得する</summary>
    Task<UsageSummary> GetUsageSummaryAsync(string memberId, string memberName, string entraId, string email, DateTime from, DateTime to);

    /// <summary>全メンバーの使用量サマリーを取得する（管理者用）</summary>
    Task<List<UsageSummary>> GetAllUsageSummariesAsync(DateTime from, DateTime to, string? memberId = null);
}
