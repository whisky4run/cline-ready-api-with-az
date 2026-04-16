using System.Text;
using System.Text.Json;
using Azure;
using ClineApiWithAz.Models.Requests;
using ClineApiWithAz.Models.Responses;
using ClineApiWithAz.Services;
using Microsoft.AspNetCore.Mvc;

namespace ClineApiWithAz.Controllers;

[ApiController]
[Route("v1")]
public class ChatCompletionsController(
    IAzureAIService azureAIService,
    ILogger<ChatCompletionsController> logger) : ControllerBase
{
    [HttpPost("chat/completions")]
    public async Task<IActionResult> ChatCompletions(
        [FromBody] ChatCompletionRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrEmpty(request.Model))
            return BadRequest(ErrorResponse.Create("'model' フィールドは必須です", "invalid_request_error", "invalid_request"));

        if (request.Messages is null || request.Messages.Count == 0)
            return BadRequest(ErrorResponse.Create("'messages' フィールドは必須です", "invalid_request_error", "invalid_request"));

        if (request.Stream)
        {
            // ストリーミングは内部でエラーを処理する（[ApiController] の content negotiation を回避）
            await HandleStreamingAsync(request, cancellationToken);
            return new EmptyResult();
        }

        try
        {
            var response = await azureAIService.CompleteChatAsync(request, cancellationToken);
            return Ok(response);
        }
        catch (ArgumentException ex)
        {
            logger.LogWarning(ex, "無効なリクエスト: {Message}", ex.Message);
            return BadRequest(ErrorResponse.Create(ex.Message, "invalid_request_error", "model_not_found"));
        }
        catch (RequestFailedException ex)
        {
            logger.LogError(ex, "Azure AI Foundry エラー: HTTP {Status}, Code={ErrorCode}, Message={Message}",
                ex.Status, ex.ErrorCode, ex.Message);
            return StatusCode(502, ErrorResponse.Create(
                $"Azure AI Foundry error: HTTP {ex.Status} ({ex.ErrorCode}) - {ex.Message}",
                "api_error", "upstream_error"));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Azure AI Foundry へのリクエストで予期しないエラーが発生しました: {Type} - {Message}",
                ex.GetType().Name, ex.Message);
            return StatusCode(502, ErrorResponse.Create(
                $"Unexpected error: {ex.GetType().Name} - {ex.Message}",
                "api_error", "upstream_error"));
        }
    }

    private async Task HandleStreamingAsync(
        ChatCompletionRequest request, CancellationToken cancellationToken)
    {
        Response.Headers.ContentType = "text/event-stream";
        Response.Headers.CacheControl = "no-cache";
        Response.Headers.Connection = "keep-alive";

        try
        {
            await foreach (var chunk in azureAIService.StreamChatAsync(request, cancellationToken))
            {
                var json = JsonSerializer.Serialize(chunk);
                await Response.WriteAsync($"data: {json}\n\n", cancellationToken);
                await Response.Body.FlushAsync(cancellationToken);
            }

            await Response.WriteAsync("data: [DONE]\n\n", cancellationToken);
            await Response.Body.FlushAsync(cancellationToken);
        }
        catch (ArgumentException ex)
        {
            logger.LogWarning(ex, "無効なリクエスト（ストリーミング）: {Message}", ex.Message);
            await WriteStreamingErrorAsync(400,
                ErrorResponse.Create(ex.Message, "invalid_request_error", "model_not_found"),
                cancellationToken);
        }
        catch (RequestFailedException ex)
        {
            logger.LogError(ex, "Azure AI Foundry エラー（ストリーミング）: HTTP {Status}, Code={ErrorCode}, Message={Message}",
                ex.Status, ex.ErrorCode, ex.Message);
            await WriteStreamingErrorAsync(502,
                ErrorResponse.Create(
                    $"Azure AI Foundry error: HTTP {ex.Status} ({ex.ErrorCode}) - {ex.Message}",
                    "api_error", "upstream_error"),
                cancellationToken);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Azure AI Foundry へのストリーミングリクエストで予期しないエラー: {Type} - {Message}",
                ex.GetType().Name, ex.Message);
            await WriteStreamingErrorAsync(502,
                ErrorResponse.Create(
                    $"Unexpected error: {ex.GetType().Name} - {ex.Message}",
                    "api_error", "upstream_error"),
                cancellationToken);
        }
    }

    private async Task WriteStreamingErrorAsync(
        int statusCode, ErrorResponse error, CancellationToken cancellationToken)
    {
        if (!Response.HasStarted)
        {
            // レスポンス未開始ならステータスコードと JSON ボディで返す
            Response.StatusCode = statusCode;
            Response.Headers.ContentType = "application/json";
            await Response.WriteAsync(JsonSerializer.Serialize(error), cancellationToken);
        }
        else
        {
            // すでにストリーム開始済みなら SSE イベントとしてエラーを通知
            var json = JsonSerializer.Serialize(error);
            await Response.WriteAsync($"data: {json}\n\n", cancellationToken);
            await Response.Body.FlushAsync(cancellationToken);
        }
    }
}
