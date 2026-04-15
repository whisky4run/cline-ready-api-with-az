using ClineApiWithAz.Models.Requests;
using ClineApiWithAz.Models.Responses;

namespace ClineApiWithAz.Services;

public interface IAzureAIService
{
    /// <summary>非ストリーミングでチャット補完を実行する</summary>
    Task<ChatCompletionResponse> CompleteChatAsync(ChatCompletionRequest request, CancellationToken cancellationToken = default);

    /// <summary>ストリーミングでチャット補完を実行し、SSE チャンクを yield する</summary>
    IAsyncEnumerable<ChatCompletionChunk> StreamChatAsync(ChatCompletionRequest request, CancellationToken cancellationToken = default);
}
