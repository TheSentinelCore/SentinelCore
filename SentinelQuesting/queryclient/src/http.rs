//! HTTP transport for [`QueryClient`] (ADR `01_ARCHITECTURE` §10).
//!
//! Talks to a running `SentinelQueryServer` over REST. GET responses are cached by URL; failed
//! transport attempts are retried with a small linear backoff. The server's DB ownership means
//! this client never touches SQLite — it only speaks HTTP.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;

use async_trait::async_trait;
use serde::de::DeserializeOwned;
use serde::Serialize;
use url::Url;

use super::{error::QueryClientError, models::*, QueryClient};

#[derive(Debug)]
pub struct HttpQueryClient {
    base_url: String,
    inner: reqwest::Client,
    cache: Mutex<HashMap<String, String>>,
    retries: usize,
}

impl Clone for HttpQueryClient {
    fn clone(&self) -> Self {
        Self {
            base_url: self.base_url.clone(),
            inner: self.inner.clone(),
            cache: Mutex::new(HashMap::new()),
            retries: self.retries,
        }
    }
}

impl HttpQueryClient {
    pub fn new(base_url: impl Into<String>) -> Self {
        let inner = reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .user_agent("sentinel-queryclient/0.1")
            .build()
            .expect("failed to build reqwest client");
        Self {
            base_url: base_url.into(),
            inner,
            cache: Mutex::new(HashMap::new()),
            retries: 3,
        }
    }

    /// Override the default retry count (3) for flaky networks.
    pub fn with_retries(mut self, retries: usize) -> Self {
        self.retries = retries;
        self
    }

    fn endpoint(&self, path: &str) -> Result<Url, QueryClientError> {
        let mut u = Url::parse(&self.base_url)
            .map_err(|e| QueryClientError::Transport(format!("invalid base url: {e}")))?;
        u.set_path(path);
        Ok(u)
    }

    async fn get_cached(&self, url: &Url) -> Result<String, QueryClientError> {
        let key = url.as_str().to_string();
        if let Some(hit) = self.cache.lock().unwrap().get(&key) {
            tracing::trace!(%key, "query cache hit");
            return Ok(hit.clone());
        }

        let mut attempt = 0usize;
        loop {
            match self.inner.get(&key).send().await {
                Ok(resp) => {
                    let status = resp.status();
                    let body = resp
                        .text()
                        .await
                        .map_err(|e| QueryClientError::Transport(e.to_string()))?;
                    if status.is_success() {
                        self.cache.lock().unwrap().insert(key, body.clone());
                        return Ok(body);
                    }
                    return Err(QueryClientError::Server {
                        status: status.as_u16(),
                        body,
                    });
                }
                Err(e) => {
                    if attempt < self.retries {
                        attempt += 1;
                        tracing::warn!(attempt, error = %e, "transport error, retrying");
                        tokio::time::sleep(Duration::from_millis(100 * attempt as u64)).await;
                        continue;
                    }
                    return Err(QueryClientError::Transport(e.to_string()));
                }
            }
        }
    }

    async fn post_json<B: Serialize + ?Sized, R: DeserializeOwned>(
        &self,
        path: &str,
        body: &B,
    ) -> Result<R, QueryClientError> {
        let url = self.endpoint(path)?;
        let resp = self
            .inner
            .post(url)
            .json(body)
            .send()
            .await
            .map_err(|e| QueryClientError::Transport(e.to_string()))?;
        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| QueryClientError::Transport(e.to_string()))?;
        if !status.is_success() {
            return Err(QueryClientError::Server {
                status: status.as_u16(),
                body: text,
            });
        }
        serde_json::from_str(&text).map_err(QueryClientError::from)
    }
}

#[async_trait]
impl QueryClient for HttpQueryClient {
    async fn search_quests(&self, query: &str) -> Result<Vec<QuestSummary>, QueryClientError> {
        let mut u = self.endpoint("/quests/search")?;
        u.query_pairs_mut().append_pair("q", query);
        let text = self.get_cached(&u).await?;
        serde_json::from_str(&text).map_err(QueryClientError::from)
    }

    async fn get_quest(&self, id: u32) -> Result<QuestDetail, QueryClientError> {
        let u = self.endpoint(&format!("/quest/{id}"))?;
        let text = self.get_cached(&u).await?;
        serde_json::from_str(&text).map_err(QueryClientError::from)
    }

    async fn search_npcs(&self, query: &str) -> Result<Vec<NpcSummary>, QueryClientError> {
        let mut u = self.endpoint("/npc/search")?;
        u.query_pairs_mut().append_pair("q", query);
        let text = self.get_cached(&u).await?;
        serde_json::from_str(&text).map_err(QueryClientError::from)
    }

    async fn get_npc(&self, entry: u32) -> Result<NpcDetail, QueryClientError> {
        let u = self.endpoint(&format!("/npc/{entry}"))?;
        let text = self.get_cached(&u).await?;
        serde_json::from_str(&text).map_err(QueryClientError::from)
    }

    async fn get_vendor(&self, entry: u32) -> Result<VendorInfo, QueryClientError> {
        let u = self.endpoint(&format!("/vendor/{entry}"))?;
        let text = self.get_cached(&u).await?;
        serde_json::from_str(&text).map_err(QueryClientError::from)
    }

    async fn get_trainer(&self, entry: u32) -> Result<TrainerInfo, QueryClientError> {
        let u = self.endpoint(&format!("/trainer/{entry}"))?;
        let text = self.get_cached(&u).await?;
        serde_json::from_str(&text).map_err(QueryClientError::from)
    }

    async fn get_flight(&self, entry: u32) -> Result<FlightInfo, QueryClientError> {
        let u = self.endpoint(&format!("/flight/{entry}"))?;
        let text = self.get_cached(&u).await?;
        serde_json::from_str(&text).map_err(QueryClientError::from)
    }

    async fn get_object(&self, entry: u32) -> Result<ObjectInfo, QueryClientError> {
        let u = self.endpoint(&format!("/object/{entry}"))?;
        let text = self.get_cached(&u).await?;
        serde_json::from_str(&text).map_err(QueryClientError::from)
    }

    async fn creatures_polygon(
        &self,
        creature_entry: u32,
    ) -> Result<CreaturePolygon, QueryClientError> {
        let mut u = self.endpoint("/creatures/polygon")?;
        u.query_pairs_mut()
            .append_pair("entry", &creature_entry.to_string());
        let text = self.get_cached(&u).await?;
        serde_json::from_str(&text).map_err(QueryClientError::from)
    }

    async fn validate(&self, req: ValidateRequest) -> Result<ValidateResponse, QueryClientError> {
        self.post_json("/validate", &req).await
    }

    async fn travel_estimate(
        &self,
        req: TravelEstimateRequest,
    ) -> Result<TravelEstimateResponse, QueryClientError> {
        self.post_json("/travel/estimate", &req).await
    }
}
