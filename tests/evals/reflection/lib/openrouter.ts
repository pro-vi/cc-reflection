/**
 * OpenRouter API client for reflection evals
 */

export interface OpenRouterResponse {
  content: string;
  promptTokens: number;
  completionTokens: number;
  latencyMs: number;
  error?: string;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function callOpenRouter(
  prompt: string,
  model: string,
  retryCount = 0
): Promise<OpenRouterResponse> {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) {
    return {
      content: "",
      promptTokens: 0,
      completionTokens: 0,
      latencyMs: 0,
      error: "OPENROUTER_API_KEY not set",
    };
  }

  const start = Date.now();

  try {
    const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/cc-reflection",
      },
      body: JSON.stringify({
        model,
        messages: [{ role: "user", content: prompt }],
        temperature: 0, // deterministic for eval
      }),
    });

    // Rate limiting - retry once
    if (res.status === 429 && retryCount < 1) {
      const retryAfter = parseInt(res.headers.get("retry-after") ?? "5", 10);
      console.log(`Rate limited, waiting ${retryAfter}s...`);
      await sleep(retryAfter * 1000);
      return callOpenRouter(prompt, model, retryCount + 1);
    }

    const json = await res.json();

    if (json.error) {
      return {
        content: "",
        promptTokens: 0,
        completionTokens: 0,
        latencyMs: Date.now() - start,
        error: json.error.message ?? JSON.stringify(json.error),
      };
    }

    return {
      content: json.choices?.[0]?.message?.content ?? "",
      promptTokens: json.usage?.prompt_tokens ?? 0,
      completionTokens: json.usage?.completion_tokens ?? 0,
      latencyMs: Date.now() - start,
    };
  } catch (err) {
    return {
      content: "",
      promptTokens: 0,
      completionTokens: 0,
      latencyMs: Date.now() - start,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

// Default models for evals
export const EVAL_MODELS = {
  fast: "openai/gpt-4o-mini",
  balanced: "google/gemini-flash-1.5",
  strong: "anthropic/claude-3.5-sonnet",
} as const;

export const DEFAULT_MODEL = EVAL_MODELS.fast;
