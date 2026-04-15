using System.Diagnostics;
using System.Text;
using System.Text.Json;
using ClineApiWithAz.Middleware;
using ClineApiWithAz.Models.Requests;
using ClineApiWithAz.Models.Responses;
using ClineApiWithAz.Services;
using Microsoft.AspNetCore.Mvc;

namespace ClineApiWithAz.Controllers;

[ApiController]
[Route("v1")]
public class ChatCompletionsController(
    IAzureAIService azureAIService,
    IUsageService usageService,
    ILogger<ChatCompletionsController> logger) : ControllerBase
{
    [HttpPost("chat/completions")]
    public async Task<IActionResult> ChatCompletions(
        [FromBody] ChatCompletionRequest request,
        CancellationToken cancellationToken)
    {
        var memberId = HttpContext.Items[ApiKeyAuthMiddleware.MemberIdKey] as string ?? string.Empty;
        var memberName = HttpContext.Items[ApiKeyAuthMiddleware.MemberNameKey] as string ?? string.Empty;
        var entraId = HttpContext.Items[ApiKeyAuthMiddleware.MemberEntraIdKey] as string ?? string.Empty;

        if (string.IsNullOrEmpty(request.Model))
            return BadRequest(ErrorResponse.Create("'model' フィールドは必須です", "invalid_request_error", "invalid_request"));

        if (request.Messages is null || request.Messages.Count == 0)
            return BadRequest(ErrorResponse.Create("'messages' フィールドは必須です", "invalid_request_error", "invalid_request"));

        var sw = Stopwatch.StartNew();

        try
        {
            if (request.Stream)
                return await HandleStreamingAsync(request, memberId, entraId, sw, cancellationToken);
            else
                return await HandleNonStreamingAsync(request, memberId, entraId, sw, cancellationToken);
        }
        catch (ArgumentException ex)
        {
            logger.LogWarning(ex, "無効なリクエスト: {Message}", ex.Message);
            return BadRequest(ErrorResponse.Create(ex.Message, "invalid_request_error", "model_not_found"));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Azure AI Foundry へのリクエストでエラーが発生しました");
            usageService.RecordUsage(memberId, entraId, request.Model, 0, 0, sw.ElapsedMilliseconds, 502);
            return StatusCode(502, ErrorResponse.Create(
                "Azure AI Foundry からのレスポンスでエラーが発生しました",
                "api_error", "upstream_error"));
        }
    }

    private async Task<IActionResult> HandleNonStreamingAsync(
        ChatCompletionRequest request, string memberId, string entraId, Stopwatch sw, CancellationToken cancellationToken)
    {
        var response = await azureAIService.CompleteChatAsync(request, cancellationToken);
        sw.Stop();

        var usage = response.Usage;
        usageService.RecordUsage(
            memberId, entraId, request.Model,
            usage?.PromptTokens ?? 0,
            usage?.CompletionTokens ?? 0,
            sw.ElapsedMilliseconds, 200);

        return Ok(response);
    }

    private async Task<IActionResult> HandleStreamingAsync(
        ChatCompletionRequest request, string memberId, string entraId, Stopwatch sw, CancellationToken cancellationToken)
    {
        Response.Headers.ContentType = "text/event-stream";
        Response.Headers.CacheControl = "no-cache";
        Response.Headers.Connection = "keep-alive";

        int promptTokens = 0, completionTokens = 0;

        await foreach (var chunk in azureAIService.StreamChatAsync(request, cancellationToken))
        {
            // 最終チャンクからトークン数を取得
            if (chunk.Usage is not null)
            {
                promptTokens = chunk.Usage.PromptTokens;
                completionTokens = chunk.Usage.CompletionTokens;
            }

            var json = JsonSerializer.Serialize(chunk);
            var line = $"data: {json}\n\n";
            await Response.Body.WriteAsync(Encoding.UTF8.GetBytes(line), cancellationToken);
            await Response.Body.FlushAsync(cancellationToken);
        }

        // 終端マーカー
        await Response.Body.WriteAsync(Encoding.UTF8.GetBytes("data: [DONE]\n\n"), cancellationToken);
        await Response.Body.FlushAsync(cancellationToken);

        sw.Stop();
        usageService.RecordUsage(memberId, entraId, request.Model, promptTokens, completionTokens, sw.ElapsedMilliseconds, 200);

        return new EmptyResult();
    }
}
