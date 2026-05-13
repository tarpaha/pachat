use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Message {
    #[serde(rename = "connect")]
    Connect {
        nickname: String,
        #[serde(rename = "publicKey")]
        public_key: String,
    },
    #[serde(rename = "peerjoined")]
    PeerJoined {
        nickname: String,
        #[serde(rename = "publicKey")]
        public_key: String,
    },
    #[serde(rename = "peerleft")]
    PeerLeft { nickname: String },
    #[serde(rename = "peerhello")]
    PeerHello {
        #[serde(skip_serializing_if = "Option::is_none")]
        to: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        from: Option<String>,
        nickname: String,
        #[serde(rename = "publicKey")]
        public_key: String,
    },
    #[serde(rename = "chat")]
    Chat {
        #[serde(skip_serializing_if = "Option::is_none")]
        to: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        from: Option<String>,
        timestamp: String,
        #[serde(rename = "encryptedKey")]
        encrypted_key: String,
        iv: String,
        ciphertext: String,
        tag: String,
    },
    #[serde(rename = "error")]
    Error { code: String, text: String },
}

impl Message {
    pub fn to_field(&self) -> Option<&str> {
        match self {
            Message::PeerHello { to, .. } => to.as_deref(),
            Message::Chat { to, .. } => to.as_deref(),
            _ => None,
        }
    }

    pub fn with_from(self, sender: String) -> Self {
        match self {
            Message::PeerHello { nickname, public_key, .. } => Message::PeerHello {
                to: None,
                from: Some(sender),
                nickname,
                public_key,
            },
            Message::Chat { timestamp, encrypted_key, iv, ciphertext, tag, .. } => Message::Chat {
                to: None,
                from: Some(sender),
                timestamp,
                encrypted_key,
                iv,
                ciphertext,
                tag,
            },
            other => other,
        }
    }
}

pub fn serialize(msg: &Message) -> String {
    serde_json::to_string(msg).unwrap_or_default()
}

pub fn deserialize(line: &str) -> serde_json::Result<Message> {
    serde_json::from_str(line)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_connect() {
        let original = r#"{"type":"connect","nickname":"alice","publicKey":"AAAA=="}"#;
        let msg = deserialize(original).expect("parse failed");
        let serialized = serialize(&msg);
        assert_eq!(original, serialized);
    }

    #[test]
    fn round_trip_peerhello() {
        let s = r#"{"type":"peerhello","to":"bob","nickname":"alice","publicKey":"AAAA=="}"#;
        let msg = deserialize(s).unwrap();
        assert_eq!(serialize(&msg), s);
    }

    #[test]
    fn with_from_clears_to() {
        let s = r#"{"type":"peerhello","to":"bob","nickname":"alice","publicKey":"AAAA=="}"#;
        let msg = deserialize(s).unwrap();
        let forwarded = msg.with_from("alice".to_string());
        let out = serialize(&forwarded);
        assert_eq!(out, r#"{"type":"peerhello","from":"alice","nickname":"alice","publicKey":"AAAA=="}"#);
    }
}
