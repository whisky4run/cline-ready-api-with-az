using System.ClientModel;
using System.Runtime.CompilerServices;
using Azure;
using Azure.AI.OpenAI;
using ClineApiWithAz.Models.Requests;
using ClineApiWithAz.Models.Responses;
using OpenAI.Chat;

namespace ClineApiWithAz.Services;

/// <summary>Azure AI Foundry の推論エンドポイントへのプロキシサービス</summary>
public class AzureAIService(IConfiguration configuration, ILogger<AzureAIService> logger) : IAzureAIService
{
    private readonly string _endpoint = configuration["AzureAI:Endpoint"]
        ?? throw new InvalidOperationException("AzureAI:Endpoint が設定されていません");
    private readonly string _apiKey = configuration["AzureAI:ApiKey"]
        ?? throw new InvalidOperationException("AzureAI:ApiKey が設定されていません");

    // モデル名 → デプロイ名のマッピング（設定がなければモデル名をそのまま使用）
    private Dictionary<string, string> ModelMappings =>
        configuration.GetSection("AzureAI:Models").Get<Dictionary<string, string>>() ?? [];

    public async Task<ChatCompletionResponse> CompleteChatAsync(
        ChatCompletionRequest request, CancellationToken cancellationToken = default)
    {
        var (chatClient, deploymentName) = CreateChatClient(request.Model);

        logger.LogInformation("Azure AI Foundry へリクエスト送信: deployment={Deployment}", deploymentName);

        var messages = BuildChatMessages(request);
        var options = BuildChatCompletionOptions(request);

        var result = await chatClient.CompleteChatAsync(messages, options, cancellationToken);
        var completion = result.Value;

        return new ChatCompletionResponse
        {
            Id = completion.Id,
            Model = request.Model,
            Created = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            Choices =
            [
                new ChatCompletionChoice
                {
                    Index = 0,
                    Message = new ChatCompletionMessage
                    {
                        Role = "assistant",
                        Content = string.Concat(completion.Content.Select(p => p.Text))
                    },
                    FinishReason = completion.FinishReason.ToString()?.ToLower()
                }
            ],
            Usage = new UsageInfo
            {
                PromptTokens = completion.Usage.InputTokenCount,
                CompletionTokens = completion.Usage.OutputTokenCount,
                TotalTokens = completion.Usage.TotalTokenCount
            }
        };
    }

    public async IAsyncEnumerable<ChatCompletionChunk> StreamChatAsync(
        ChatCompletionRequest request,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var (chatClient, deploymentName) = CreateChatClient(request.Model);

        logger.LogInformation("Azure AI Foundry へストリーミングリクエスト送信: deployment={Deployment}", deploymentName);

        var messages = BuildChatMessages(request);
        var options = BuildChatCompletionOptions(request);

        var streamingResult = chatClient.CompleteChatStreamingAsync(messages, options, cancellationToken);

        var completionId = $"chatcmpl-{Guid.NewGuid():N}";
        var created = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        bool isFirst = true;

        await foreach (var update in streamingResult.WithCancellation(cancellationToken))
        {
            var contentText = string.Concat(update.ContentUpdate.Select(p => p.Text));

            var chunk = new ChatCompletionChunk
            {
                Id = completionId,
                Created = created,
                Model = request.Model,
                Choices =
                [
                    new ChatCompletionChunkChoice
                    {
                        Index = 0,
                        Delta = new ChatCompletionDelta
                        {
                            Role = isFirst ? "assistant" : null,
                            Content = contentText
                        },
                        FinishReason = update.FinishReason?.ToString()?.ToLower()
                    }
                ],
                Usage = update.Usage is not null ? new UsageInfo
                {
                    PromptTokens = update.Usage.InputTokenCount,
                    CompletionTokens = update.Usage.OutputTokenCount,
                    TotalTokens = update.Usage.TotalTokenCount
                } : null
            };

            isFirst = false;
            yield return chunk;
        }
    }

    private (ChatClient chatClient, string deploymentName) CreateChatClient(string modelName)
    {
        var deploymentName = ModelMappings.TryGetValue(modelName, out var mapped)
            ? mapped
            : modelName;

        logger.LogDebug("AI Foundry エンドポイント: {Endpoint}, デプロイ名: {Deployment}", _endpoint, deploymentName);

        var azureClient = new AzureOpenAIClient(
            new Uri(_endpoint),
            new AzureKeyCredential(_apiKey));

        return (azureClient.GetChatClient(deploymentName), deploymentName);
    }

    private static List<OpenAI.Chat.ChatMessage> BuildChatMessages(ChatCompletionRequest request)
    {
        var messages = new List<OpenAI.Chat.ChatMessage>();
        foreach (var msg in request.Messages)
        {
            var text = msg.GetTextContent();
            OpenAI.Chat.ChatMessage chatMsg = msg.Role switch
            {
                "system" => new SystemChatMessage(text),
                "assistant" => new AssistantChatMessage(text),
                _ => new UserChatMessage(text)
            };
            messages.Add(chatMsg);
        }
        return messages;
    }

    private static ChatCompletionOptions BuildChatCompletionOptions(ChatCompletionRequest request)
    {
        var options = new ChatCompletionOptions();

        if (request.Temperature.HasValue) options.Temperature = request.Temperature;
        if (request.MaxTokens.HasValue) options.MaxOutputTokenCount = request.MaxTokens;
        if (request.TopP.HasValue) options.TopP = request.TopP;
        if (request.FrequencyPenalty.HasValue) options.FrequencyPenalty = request.FrequencyPenalty;
        if (request.PresencePenalty.HasValue) options.PresencePenalty = request.PresencePenalty;

        return options;
    }
}
