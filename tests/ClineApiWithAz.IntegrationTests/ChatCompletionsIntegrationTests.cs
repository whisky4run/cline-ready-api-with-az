using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using ClineApiWithAz.Models.Domain;
using ClineApiWithAz.Models.Requests;
using ClineApiWithAz.Models.Responses;
using Moq;

namespace ClineApiWithAz.IntegrationTests;

public class ChatCompletionsIntegrationTests : IClassFixture<TestWebApplicationFactory>
{
    private readonly TestWebApplicationFactory _factory;
    private readonly HttpClient _client;

    private static readonly Member TestMember = new()
    {
        Id = "m-001", Name = "Alice", Role = "member", IsActive = true
    };
    private const string TestApiKey = "sk-alice-test";

    public ChatCompletionsIntegrationTests(TestWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
        factory.SetupMember(TestApiKey, TestMember);
    }

    // ─── 認証テスト ───────────────────────────────────────────────

    [Fact]
    public async Task APIキーなし_401を返す()
    {
        var response = await _client.PostAsJsonAsync("/v1/chat/completions", new
        {
            model = "gpt-4.1-mini",
            messages = new[] { new { role = "user", content = "Hi" } }
        });

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        var error = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        Assert.Equal("invalid_api_key", error!.Error.Code);
    }

    [Fact]
    public async Task 無効なAPIキー_401を返す()
    {
        _factory.SetupInvalidApiKey("bad-key");
        var request = new HttpRequestMessage(HttpMethod.Post, "/v1/chat/completions");
        request.Headers.Add("Authorization", "Bearer bad-key");
        request.Content = JsonContent.Create(new
        {
            model = "gpt-4.1-mini",
            messages = new[] { new { role = "user", content = "Hi" } }
        });

        var response = await _client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // ─── 非ストリーミングテスト ────────────────────────────────────

    [Fact]
    public async Task 非ストリーミング_正常リクエスト_200とOpenAI互換レスポンスを返す()
    {
        // Arrange
        _factory.AiServiceMock
            .Setup(s => s.CompleteChatAsync(It.IsAny<ChatCompletionRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ChatCompletionResponse
            {
                Id = "chatcmpl-abc",
                Model = "gpt-4.1-mini",
                Choices = [new() { Index = 0, Message = new() { Role = "assistant", Content = "Hello!" }, FinishReason = "stop" }],
                Usage = new() { PromptTokens = 10, CompletionTokens = 5, TotalTokens = 15 }
            });

        var request = CreateRequest(new
        {
            model = "gpt-4.1-mini",
            messages = new[] { new { role = "user", content = "Hello" } },
            stream = false
        });

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<ChatCompletionResponse>();
        Assert.Equal("chatcmpl-abc", body!.Id);
        Assert.Equal("chat.completion", body.Object);
        Assert.Equal("Hello!", body.Choices[0].Message.Content);
        Assert.Equal("stop", body.Choices[0].FinishReason);
        Assert.Equal(15, body.Usage!.TotalTokens);
    }

    [Fact]
    public async Task 非ストリーミング_modelなし_400を返す()
    {
        var request = CreateRequest(new
        {
            messages = new[] { new { role = "user", content = "Hello" } }
        });

        var response = await _client.SendAsync(request);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    // ─── ストリーミングテスト ─────────────────────────────────────

    [Fact]
    public async Task ストリーミング_SSEチャンクとDONEマーカーを返す()
    {
        // Arrange
        _factory.AiServiceMock
            .Setup(s => s.StreamChatAsync(It.IsAny<ChatCompletionRequest>(), It.IsAny<CancellationToken>()))
            .Returns(CreateChunks("Hello", " World"));

        var request = CreateRequest(new
        {
            model = "gpt-4.1-mini",
            messages = new[] { new { role = "user", content = "Hi" } },
            stream = true
        });

        // Act
        var response = await _client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);
        var body = await response.Content.ReadAsStringAsync();

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("text/event-stream", response.Content.Headers.ContentType?.MediaType);
        Assert.Contains("data: ", body);
        Assert.Contains("[DONE]", body);

        // 各チャンクが JSON パースできることを確認
        var lines = body.Split('\n', StringSplitOptions.RemoveEmptyEntries)
            .Where(l => l.StartsWith("data: ") && !l.Contains("[DONE]"))
            .Select(l => l["data: ".Length..]);
        foreach (var line in lines)
        {
            var chunk = JsonSerializer.Deserialize<ChatCompletionChunk>(line);
            Assert.Equal("chat.completion.chunk", chunk!.Object);
        }
    }

    // ─── モデル一覧テスト ─────────────────────────────────────────

    [Fact]
    public async Task GetModels_gpt41miniを含むモデル一覧を返す()
    {
        var request = new HttpRequestMessage(HttpMethod.Get, "/v1/models");
        request.Headers.Add("Authorization", $"Bearer {TestApiKey}");

        var response = await _client.SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<ModelsResponse>();
        Assert.Equal("list", body!.Object);
        Assert.Contains(body.Data, m => m.Id == "gpt-4.1-mini");
    }

    // ─── 使用量テスト ─────────────────────────────────────────────

    [Fact]
    public async Task GetMyUsage_自分の使用量を返す()
    {
        // Arrange
        _factory.UsageServiceMock
            .Setup(s => s.GetUsageSummaryAsync("m-001", "Alice", It.IsAny<string>(), It.IsAny<string>(), It.IsAny<DateTime>(), It.IsAny<DateTime>()))
            .ReturnsAsync(new UsageSummary
            {
                MemberId = "m-001", MemberName = "Alice",
                TotalPromptTokens = 500, TotalCompletionTokens = 250,
                TotalTokens = 750, RequestCount = 5
            });

        var request = new HttpRequestMessage(HttpMethod.Get, "/v1/usage/me");
        request.Headers.Add("Authorization", $"Bearer {TestApiKey}");

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<MyUsageResponse>();
        Assert.Equal("m-001", body!.MemberId);
        Assert.Equal(750, body.TotalTokens);
        Assert.NotNull(body.Period);
    }

    [Fact]
    public async Task GetAllUsage_一般メンバーは403を返す()
    {
        var request = new HttpRequestMessage(HttpMethod.Get, "/v1/usage");
        request.Headers.Add("Authorization", $"Bearer {TestApiKey}");

        var response = await _client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task GetAllUsage_管理者は全使用量を返す()
    {
        // Arrange
        var adminMember = new Member { Id = "m-admin", Name = "Admin", Role = "admin", IsActive = true };
        _factory.SetupMember("admin-key", adminMember);

        _factory.UsageServiceMock
            .Setup(s => s.GetAllUsageSummariesAsync(It.IsAny<DateTime>(), It.IsAny<DateTime>(), null))
            .ReturnsAsync([
                new UsageSummary { MemberId = "m-001", MemberName = "Alice", TotalTokens = 1000 }
            ]);

        var request = new HttpRequestMessage(HttpMethod.Get, "/v1/usage");
        request.Headers.Add("Authorization", "Bearer admin-key");

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<UsageSummaryListResponse>();
        Assert.Single(body!.Data);
    }

    // ─── ヘルパー ─────────────────────────────────────────────────

    private HttpRequestMessage CreateRequest(object body)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/v1/chat/completions");
        request.Headers.Add("Authorization", $"Bearer {TestApiKey}");
        request.Content = new StringContent(
            JsonSerializer.Serialize(body),
            Encoding.UTF8,
            "application/json");
        return request;
    }

    private static async IAsyncEnumerable<ChatCompletionChunk> CreateChunks(params string[] contents)
    {
        foreach (var content in contents)
        {
            yield return new ChatCompletionChunk
            {
                Id = "chatcmpl-test",
                Model = "gpt-4.1-mini",
                Choices = [new() { Index = 0, Delta = new() { Content = content } }]
            };
            await Task.Yield();
        }
    }
}
