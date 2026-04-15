using System.Runtime.CompilerServices;
using Azure;
using Azure.AI.Inference;
using ClineApiWithAz.Models.Requests;
using ClineApiWithAz.Models.Responses;

namespace ClineApiWithAz.Services;

/// <summary>Azure AI Foundry の推論エンドポイントへのプロキシサービス</summary>
public class AzureAIService(IConfiguration configuration, ILogger<AzureAIService> logger) : IAzureAIService
{
    private readonly string _endpoint = configuration["AzureAI:Endpoint"]
        ?? throw new InvalidOperationException("AzureAI:Endpoint が設定されていません");
    private readonly string _apiKey = configuration["AzureAI:ApiKey"]
        ?? throw new InvalidOperationException("AzureAI:ApiKey が設定されていません");

    // モデル名 → デプロイ URI のマッピング
    private Dictionary<string, string> ModelMappings =>
        configuration.GetSection("AzureAI:Models").Get<Dictionary<string, string>>() ?? [];

    public async Task<ChatCompletionResponse> CompleteChatAsync(
        ChatCompletionRequest request, CancellationToken cancellationToken = default)
    {
        var client = CreateClient();
        var options = BuildChatCompletionsOptions(request);

        logger.LogInformation("Azure AI Foundry へリクエスト送信: model={Model}", request.Model);

        var response = await client.CompleteAsync(options, cancellationToken);
        // Azure.AI.Inference beta.5: ChatCompletions は Choices を持たず、Content が直接格納される
        var completion = response.Value;

        return new ChatCompletionResponse
        {
            Id = completion.Id,
            Model = request.Model,
            Created = completion.Created.ToUnixTimeSeconds(),
            Choices =
            [
                new ChatCompletionChoice
                {
                    Index = 0,
                    Message = new ChatCompletionMessage
                    {
                        Role = "assistant",
                        Content = completion.Content
                    },
                    FinishReason = completion.FinishReason?.ToString()?.ToLower()
                }
            ],
            Usage = completion.Usage is not null ? new UsageInfo
            {
                PromptTokens = completion.Usage.PromptTokens,
                CompletionTokens = completion.Usage.CompletionTokens,
                TotalTokens = completion.Usage.TotalTokens
            } : null
        };
    }

    public async IAsyncEnumerable<ChatCompletionChunk> StreamChatAsync(
        ChatCompletionRequest request,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var client = CreateClient();
        var options = BuildChatCompletionsOptions(request);

        logger.LogInformation("Azure AI Foundry へストリーミングリクエスト送信: model={Model}", request.Model);

        var streamingResponse = await client.CompleteStreamingAsync(options, cancellationToken);

        var completionId = $"chatcmpl-{Guid.NewGuid():N}";
        var created = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        bool isFirst = true;

        // StreamingChatCompletionsUpdate は ContentUpdate, FinishReason, Usage を直接持つ
        await foreach (var update in streamingResponse.WithCancellation(cancellationToken))
        {
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
                            Content = update.ContentUpdate
                        },
                        FinishReason = update.FinishReason?.ToString()?.ToLower()
                    }
                ],
                // 最終チャンクにのみ usage が含まれる
                Usage = update.Usage is not null ? new UsageInfo
                {
                    PromptTokens = update.Usage.PromptTokens,
                    CompletionTokens = update.Usage.CompletionTokens,
                    TotalTokens = update.Usage.TotalTokens
                } : null
            };

            isFirst = false;
            yield return chunk;
        }
    }

    private ChatCompletionsClient CreateClient()
    {
        return new ChatCompletionsClient(
            new Uri(_endpoint),
            new AzureKeyCredential(_apiKey));
    }

    private ChatCompletionsOptions BuildChatCompletionsOptions(ChatCompletionRequest request)
    {
        // モデル名を AI Foundry のデプロイ URI にマッピング
        if (!ModelMappings.TryGetValue(request.Model, out var deploymentUri))
        {
            throw new ArgumentException($"モデル '{request.Model}' は設定に存在しません");
        }

        var options = new ChatCompletionsOptions
        {
            Model = deploymentUri
        };

        foreach (var msg in request.Messages)
        {
            ChatRequestMessage chatMsg = msg.Role switch
            {
                "system" => new ChatRequestSystemMessage(msg.Content),
                "assistant" => new ChatRequestAssistantMessage(msg.Content),
                _ => new ChatRequestUserMessage(msg.Content)
            };
            options.Messages.Add(chatMsg);
        }

        if (request.Temperature.HasValue) options.Temperature = request.Temperature;
        if (request.MaxTokens.HasValue) options.MaxTokens = request.MaxTokens;
        if (request.TopP.HasValue) options.NucleusSamplingFactor = request.TopP;
        if (request.FrequencyPenalty.HasValue) options.FrequencyPenalty = request.FrequencyPenalty;
        if (request.PresencePenalty.HasValue) options.PresencePenalty = request.PresencePenalty;

        return options;
    }
}
