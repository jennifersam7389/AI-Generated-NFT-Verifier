# 🤖 AI-Generated NFT Verifier

A Clarity smart contract for verifying AI-generated NFTs on the Stacks blockchain. This contract enables certified verifiers to authenticate NFTs using registered AI models and provides confidence scores for verification results.

## ✨ Features

- 🔍 **NFT Verification**: Verify if NFTs are AI-generated with confidence scores
- 🧠 **AI Model Registry**: Register and manage different AI detection models  
- 👨‍💼 **Certified Verifiers**: Only certified verifiers can submit verification results
- 💰 **Fee-based System**: Pay-per-verification model with configurable fees
- 📊 **Reputation Tracking**: Track verifier performance and reputation scores
- 🔒 **Metadata Validation**: Verify NFT metadata integrity using hash verification

## 🚀 Quick Start

### Prerequisites

- Clarinet CLI installed
- Stacks wallet for testing

### Installation

```bash
clarinet new ai-nft-verifier
cd ai-nft-verifier
```

Copy the contract code into `contracts/ai-generated-nft-verifier.clar`

### Testing

```bash
clarinet console
```

## 📖 Usage

### For Contract Owner

#### Register AI Model
```clarity
(contract-call? .ai-generated-nft-verifier register-ai-model "gpt-vision-v1" "GPT Vision Model" "1.0" u85)
```

#### Certify Verifier
```clarity
(contract-call? .ai-generated-nft-verifier certify-verifier 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

### For Users

#### Request Verification
```clarity
(contract-call? .ai-generated-nft-verifier request-verification 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM u1 "gpt-vision-v1")
```

#### Check NFT Verification Status
```clarity
(contract-call? .ai-generated-nft-verifier is-nft-ai-verified 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM u1)
```

### For Certified Verifiers

#### Submit Verification Result
```clarity
(contract-call? .ai-generated-nft-verifier submit-verification u1 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM u1 "gpt-vision-v1" u92 0x1234567890abcdef)
```

## 🔧 Contract Functions

### Public Functions

| Function | Description |
|----------|-------------|
| `register-ai-model` | Register new AI detection model (owner only) |
| `certify-verifier` | Certify a verifier (owner only) |
| `request-verification` | Request NFT verification (pays fee) |
| `submit-verification` | Submit verification result (certified verifiers only) |
| `update-verification-fee` | Update verification fee (owner only) |

### Read-Only Functions

| Function | Description |
|----------|-------------|
| `get-nft-verification` | Get complete verification data for NFT |
| `is-nft-ai-verified` | Check if NFT is verified as AI-generated |
| `get-verification-confidence` | Get confidence score for verified NFT |
| `get-verifier-reputation` | Get verifier's reputation score |
| `get-ai-model-info` | Get AI model details |

## 💡 Key Concepts

### Verification Process
1. 📝 User requests verification and pays fee
2. 🔍 Certified verifier analyzes NFT using registered AI model
3. 📊 Verifier submits confidence score and metadata hash
4. ✅ NFT marked as verified if confidence exceeds model threshold

### Confidence Scoring
- 📈 Scale: 0-100
- 🎯 Each AI model has accuracy threshold (70-100)
- ✨ NFT verified if confidence ≥ threshold

### Reputation System
- 🏆 Verifiers earn reputation through successful verifications
- 📊 Tracks total and successful verification counts
- 🔒 Only certified verifiers can submit results

## 🛡️ Security Features

- 👑 Owner-only administrative functions
- 🎫 Certified verifier requirements
- 💰 Fee-based spam prevention
- 🔐 Metadata hash verification
- ❌ Duplicate verification prevention

## 🧪 Testing Examples

```clarity
;; Register AI model
(contract-call? .ai-generated-nft-verifier register-ai-model "dalle-detector" "DALL-E Detector" "2.0" u80)

;; Certify verifier
(contract-call? .ai-generated-nft-verifier certify-verifier 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)

;; Request and complete verification
(contract-call? .ai-generated-nft-verifier request-verification 'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG u123 "dalle-detector")
(contract-call? .ai-generated-nft-verifier submit-verification u1 'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG u123 "dalle-detector" u85 0xabcdef1234567890)
```

## 📄 License

MIT License - Feel free to use and modify! 🎉
```

**Git Commit Message:**
```
feat: implement AI-generated NFT verifier contract with metadata validation

