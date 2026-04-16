using System.Text;
using System.Text.Json;
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

        try
        {
            if (request.Stream)
                return await HandleStreamingAsync(request, cancellationToken);
            else
                return await HandleNonStreamingAsync(request, cancellationToken);
        }
        catch (ArgumentException ex)
        {
            logger.LogWarning(ex, "無効なリクエスト: {Message}", ex.Message);
            return BadRequest(ErrorResponse.Create(ex.Message, "invalid_request_error", "model_not_found"));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Azure AI Foundry へのリクエストでエラーが発生しました");
            return StatusCode(502, ErrorResponse.Create(
                "Azure AI Foundry からのレスポンスでエラーが発生しました",
                "api_error", "upstream_error"));
        }
    }

    private async Task<IActionResult> HandleNonStreamingAsync(
        ChatCompletionRequest request, CancellationToken cancellationToken)
    {
        var response = await azureAIService.CompleteChatAsync(request, cancellationToken);
        return Ok(response);
    }

    private async Task<IActionResult> HandleStreamingAsync(
        ChatCompletionRequest request, CancellationToken cancellationToken)
    {
        Response.Headers.ContentType = "text/event-stream";
        Response.Headers.CacheControl = "no-cache";
        Response.Headers.Connection = "keep-alive";

        await foreach (var chunk in azureAIService.StreamChatAsync(request, cancellationToken))
        {
            var json = JsonSerializer.Serialize(chunk);
            var line = $"data: {json}\n\n";
            await Response.Body.WriteAsync(Encoding.UTF8.GetBytes(line), cancellationToken);
            await Response.Body.FlushAsync(cancellationToken);
        }

        await Response.Body.WriteAsync(Encoding.UTF8.GetBytes("data: [DONE]\n\n"), cancellationToken);
        await Response.Body.FlushAsync(cancellationToken);

        return new EmptyResult();
    }
}
