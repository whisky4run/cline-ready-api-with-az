using System.Text.Json;
using ClineApiWithAz.Controllers;
using ClineApiWithAz.Models.Requests;
using ClineApiWithAz.Models.Responses;
using ClineApiWithAz.Services;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;

namespace ClineApiWithAz.UnitTests.Controllers;

public class ChatCompletionsControllerTests
{
    private readonly Mock<IAzureAIService> _aiServiceMock = new();

    private ChatCompletionsController CreateController()
    {
        var controller = new ChatCompletionsController(
            _aiServiceMock.Object,
            NullLogger<ChatCompletionsController>.Instance);
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext()
        };
        return controller;
    }

    [Fact]
    public async Task 非ストリーミングリクエスト_正常レスポンスを返す()
    {
        // Arrange
        var expectedResponse = new ChatCompletionResponse
        {
            Id = "chatcmpl-test",
            Model = "gpt-4.1-mini",
            Choices = [new() { Index = 0, Message = new() { Role = "assistant", Content = "Hello!" }, FinishReason = "stop" }],
            Usage = new() { PromptTokens = 10, CompletionTokens = 5, TotalTokens = 15 }
        };
        _aiServiceMock
            .Setup(s => s.CompleteChatAsync(It.IsAny<ChatCompletionRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(expectedResponse);

        var controller = CreateController();
        var request = new ChatCompletionRequest
        {
            Model = "gpt-4.1-mini",
            Messages = [new() { Role = "user", Content = JsonSerializer.SerializeToElement("Hello") }],
            Stream = false
        };

        // Act
        var result = await controller.ChatCompletions(request, CancellationToken.None);

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<ChatCompletionResponse>(okResult.Value);
        Assert.Equal("chatcmpl-test", response.Id);
        Assert.Equal("Hello!", response.Choices[0].Message.Content);
    }

    [Fact]
    public async Task modelフィールドがない場合_400を返す()
    {
        var controller = CreateController();
        var request = new ChatCompletionRequest
        {
            Model = "",
            Messages = [new() { Role = "user", Content = JsonSerializer.SerializeToElement("Hello") }]
        };

        var result = await controller.ChatCompletions(request, CancellationToken.None);

        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        var error = Assert.IsType<ErrorResponse>(badRequest.Value);
        Assert.Equal("invalid_request", error.Error.Code);
    }

    [Fact]
    public async Task messagesが空の場合_400を返す()
    {
        var controller = CreateController();
        var request = new ChatCompletionRequest
        {
            Model = "gpt-4.1-mini",
            Messages = []
        };

        var result = await controller.ChatCompletions(request, CancellationToken.None);

        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        var error = Assert.IsType<ErrorResponse>(badRequest.Value);
        Assert.Equal("invalid_request", error.Error.Code);
    }

    [Fact]
    public async Task 存在しないモデルの場合_400を返す()
    {
        _aiServiceMock
            .Setup(s => s.CompleteChatAsync(It.IsAny<ChatCompletionRequest>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new ArgumentException("モデル 'unknown' は設定に存在しません"));

        var controller = CreateController();
        var request = new ChatCompletionRequest
        {
            Model = "unknown",
            Messages = [new() { Role = "user", Content = JsonSerializer.SerializeToElement("Hello") }]
        };

        var result = await controller.ChatCompletions(request, CancellationToken.None);

        var badRequest = Assert.IsType<BadRequestObjectResult>(result);
        var error = Assert.IsType<ErrorResponse>(badRequest.Value);
        Assert.Equal("model_not_found", error.Error.Code);
    }

    [Fact]
    public async Task AI呼び出しで例外が発生した場合_502を返す()
    {
        _aiServiceMock
            .Setup(s => s.CompleteChatAsync(It.IsAny<ChatCompletionRequest>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new HttpRequestException("upstream error"));

        var controller = CreateController();
        var request = new ChatCompletionRequest
        {
            Model = "gpt-4.1-mini",
            Messages = [new() { Role = "user", Content = JsonSerializer.SerializeToElement("Hello") }]
        };

        var result = await controller.ChatCompletions(request, CancellationToken.None);

        var objectResult = Assert.IsType<ObjectResult>(result);
        Assert.Equal(502, objectResult.StatusCode);
        var error = Assert.IsType<ErrorResponse>(objectResult.Value);
        Assert.Equal("upstream_error", error.Error.Code);
    }
}
