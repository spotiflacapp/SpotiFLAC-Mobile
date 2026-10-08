use super::coordinator::SignedSessionClient;
use super::protocol::{self, ErrorContract};
use serde_json::Value;
use std::collections::BTreeMap;

impl SignedSessionClient {
    pub fn signed_fetch(
        &self,
        method: &str,
        path: &str,
        body: &str,
        headers: &BTreeMap<String, String>,
        check: impl Fn() -> Result<(), String>,
    ) -> Result<Value, String> {
        self.check(&check)?;
        let method = method.trim().to_uppercase();
        let mut record = {
            let state = self.scope.lock().expect("signed session coordinator lock");
            let mut record = self.load()?;
            let error = if record.session_id.is_empty() || record.session_secret.is_empty() {
                Some("signed session is not authenticated")
            } else if protocol::parse_time(&record.expires_at)
                .is_some_and(|expires| self.registry.auth.now() > expires)
            {
                record.clear();
                let _ = self.store.save(&record);
                Some("signed session expired")
            } else {
                None
            };
            if let Some(error) = error {
                drop(state);
                let url = match self.bootstrap(&check) {
                    Ok(url) => url,
                    Err(_) => {
                        return on_mint_failure(
                            || self.check(&check),
                            || self.verification_required(String::new()),
                        );
                    }
                };
                return if url.is_empty() {
                    Err(error.into())
                } else {
                    Ok(self.verification_required(url))
                };
            }
            if state.blocked(&record) {
                drop(state);
                let url = match self.bootstrap(&check) {
                    Ok(url) => url,
                    Err(_) => {
                        return on_mint_failure(
                            || self.check(&check),
                            || self.verification_required(String::new()),
                        );
                    }
                };
                if !url.is_empty() {
                    return Ok(self.verification_required(url));
                }
                let state = self.scope.lock().expect("signed session coordinator lock");
                record = self.load()?;
                if !record.usable(self.registry.auth.now()) || state.blocked(&record) {
                    return on_mint_failure(
                        || self.check(&check),
                        || self.verification_required(String::new()),
                    );
                }
            }
            record
        };
        if record.refresh_due(&self.config, self.registry.auth.now()) {
            let _ = self.refresh(&check);
            self.check(&check)?;
            let state = self.scope.lock().expect("signed session coordinator lock");
            let latest = self.load()?;
            if !latest.usable(self.registry.auth.now()) || state.blocked(&latest) {
                drop(state);
                let url = self.bootstrap(&check)?;
                return if url.is_empty() {
                    Err("signed session is not authenticated".into())
                } else {
                    Ok(self.verification_required(url))
                };
            }
            record = latest;
        }
        let mut session_retries = 0;
        let mut provider_retries = 0;
        let mut request_auth_retry = false;
        loop {
            let response = self.signed_request(&record, &method, path, body, headers, &check)?;
            let contract = ErrorContract::parse(&response.body);
            if contract.provider_retry(response.status) {
                if provider_retries >= 2 {
                    return Ok(protocol::response_value(response, self.registry.auth.now()));
                }
                provider_retries += 1;
                self.wait(
                    protocol::provider_delay(&response, &contract, self.registry.auth.now()),
                    &check,
                )?;
                continue;
            }
            if contract.request_auth_invalid(response.status) {
                let _state = self.scope.lock().expect("signed session coordinator lock");
                let latest = self.load()?;
                if !request_auth_retry
                    && latest.usable(self.registry.auth.now())
                    && !latest.same_session(&record)
                {
                    request_auth_retry = true;
                    record = latest;
                    continue;
                }
                return Ok(protocol::response_value(response, self.registry.auth.now()));
            }
            let action = contract.gateway_action(response.status);
            if action.is_empty() {
                return Ok(protocol::response_value(response, self.registry.auth.now()));
            }
            let mut state = self.scope.lock().expect("signed session coordinator lock");
            let mut latest = self.load()?;
            if latest.usable(self.registry.auth.now()) && !latest.same_session(&record) {
                if session_retries >= 1 {
                    return Err("signed-session retry limit reached".into());
                }
                session_retries += 1;
                record = latest;
                continue;
            }
            if action == "bootstrap_session" && latest.same_session(&record) {
                state.blocked_generation.clear();
                latest.clear();
                self.store.save(&latest)?;
            } else if action == "verify" && latest.same_session(&record) {
                state.blocked_generation = record.generation();
            }
            drop(state);
            let url = self.bootstrap(&check)?;
            if !url.is_empty() {
                return Ok(self.verification_required(url));
            }
            let _state = self.scope.lock().expect("signed session coordinator lock");
            let bootstrapped = self.load()?;
            if bootstrapped.usable(self.registry.auth.now())
                && !bootstrapped.same_session(&record)
                && session_retries < 1
            {
                session_retries += 1;
                record = bootstrapped;
                continue;
            }
            return Ok(protocol::response_value(response, self.registry.auth.now()));
        }
    }
}

fn on_mint_failure<T>(
    recheck: impl FnOnce() -> Result<(), String>,
    verification: impl FnOnce() -> T,
) -> Result<T, String> {
    recheck()?;
    Ok(verification())
}

#[cfg(test)]
mod signed_session_mint_tests {
    use super::on_mint_failure;

    #[test]
    fn mint_failure_becomes_verification_required() {
        let out = on_mint_failure(|| Ok(()), || serde_json::json!({"needsVerification": true}));
        assert_eq!(out.unwrap()["needsVerification"], true);
    }

    #[test]
    fn mint_failure_propagates_cancellation() {
        let out = on_mint_failure(|| Err("download cancelled".to_string()), || 1);
        assert_eq!(out.unwrap_err(), "download cancelled");
    }
}
