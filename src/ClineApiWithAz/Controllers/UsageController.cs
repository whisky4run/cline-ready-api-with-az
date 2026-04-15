using ClineApiWithAz.Middleware;
using ClineApiWithAz.Models.Responses;
using ClineApiWithAz.Services;
using Microsoft.AspNetCore.Mvc;

namespace ClineApiWithAz.Controllers;

[ApiController]
[Route("v1/usage")]
public class UsageController(IUsageService usageService) : ControllerBase
{
    /// <summary>自分の使用量を取得する（全メンバー向け）</summary>
    [HttpGet("me")]
    public async Task<IActionResult> GetMyUsage(
        [FromQuery] string? from,
        [FromQuery] string? to)
    {
        var memberId = HttpContext.Items[ApiKeyAuthMiddleware.MemberIdKey] as string ?? string.Empty;
        var memberName = HttpContext.Items[ApiKeyAuthMiddleware.MemberNameKey] as string ?? string.Empty;
        var entraId = HttpContext.Items[ApiKeyAuthMiddleware.MemberEntraIdKey] as string ?? string.Empty;
        var email = HttpContext.Items[ApiKeyAuthMiddleware.MemberEmailKey] as string ?? string.Empty;

        var (fromDate, toDate) = ParsePeriod(from, to);
        var summary = await usageService.GetUsageSummaryAsync(memberId, memberName, entraId, email, fromDate, toDate);

        return Ok(new MyUsageResponse
        {
            MemberId = summary.MemberId,
            MemberName = summary.MemberName,
            EntraId = summary.EntraId,
            Email = summary.Email,
            TotalPromptTokens = summary.TotalPromptTokens,
            TotalCompletionTokens = summary.TotalCompletionTokens,
            TotalTokens = summary.TotalTokens,
            RequestCount = summary.RequestCount,
            Period = new UsagePeriod
            {
                From = fromDate.ToString("yyyy-MM-dd"),
                To = toDate.ToString("yyyy-MM-dd")
            }
        });
    }

    /// <summary>全メンバーの使用量を取得する（管理者専用）</summary>
    [HttpGet]
    public async Task<IActionResult> GetAllUsage(
        [FromQuery] string? from,
        [FromQuery] string? to,
        [FromQuery(Name = "member_id")] string? memberId)
    {
        var role = HttpContext.Items[ApiKeyAuthMiddleware.MemberRoleKey] as string;
        if (role != "admin")
        {
            return StatusCode(403, ErrorResponse.Create(
                "この操作には管理者権限が必要です",
                "invalid_request_error", "permission_denied"));
        }

        var (fromDate, toDate) = ParsePeriod(from, to);
        var summaries = await usageService.GetAllUsageSummariesAsync(fromDate, toDate, memberId);

        return Ok(new UsageSummaryListResponse { Data = summaries });
    }

    private static (DateTime from, DateTime to) ParsePeriod(string? from, string? to)
    {
        // デフォルトは当月
        var now = DateTime.UtcNow;
        var fromDate = string.IsNullOrEmpty(from)
            ? new DateTime(now.Year, now.Month, 1, 0, 0, 0, DateTimeKind.Utc)
            : DateTime.Parse(from, null, System.Globalization.DateTimeStyles.AssumeUniversal).ToUniversalTime();
        var toDate = string.IsNullOrEmpty(to)
            ? new DateTime(now.Year, now.Month, DateTime.DaysInMonth(now.Year, now.Month), 23, 59, 59, DateTimeKind.Utc)
            : DateTime.Parse(to, null, System.Globalization.DateTimeStyles.AssumeUniversal).ToUniversalTime();

        return (fromDate, toDate);
    }
}
