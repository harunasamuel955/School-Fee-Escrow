# 🎓 School Fee Escrow Smart Contract

A secure, decentralized escrow system for managing school fee payments on the Stacks blockchain. This smart contract provides transparent, trustless fee management between students and educational institutions.

## 🌟 Features

- 🔒 **Secure Escrow System**: Funds are locked until conditions are met
- 🏫 **School Registration**: Educational institutions can register and set fees
- ⏰ **Time-based Release**: Automatic payment release after deadline
- 🔄 **Refund Mechanism**: Students can get refunds before deadline
- ⚖️ **Dispute Resolution**: Built-in dispute handling system
- 💰 **Platform Fees**: Configurable fee structure for platform sustainability
- 📊 **Analytics**: Track platform statistics and transaction history

## 🚀 Quick Start

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Stacks wallet with STX tokens

### Installation

```bash
git clone https://github.com/harunasamuel955/School-Fee-Escrow
cd School-Fee-Escrow
clarinet check
```

## 📋 Usage Guide

### For Schools 🏫

#### 1. Register Your Institution
```clarity
(contract-call? .School-Fee-Escrow register-school "University Name" u1000000)
```

#### 2. Update Registration Fee
```clarity
(contract-call? .School-Fee-Escrow update-school-registration-fee u1200000)
```

#### 3. Release Payment After Deadline
```clarity
(contract-call? .School-Fee-Escrow release-payment u1)
```

### For Students 👨‍🎓

#### 1. Create Fee Escrow
```clarity
(contract-call? .School-Fee-Escrow create-escrow 'SP1SCHOOL123... u5000000 u144)
```
*Creates escrow for 50 STX with 144 block deadline (~1 day)*

#### 2. Request Refund (Before Deadline)
```clarity
(contract-call? .School-Fee-Escrow refund-payment u1)
```

#### 3. Extend Deadline
```clarity
(contract-call? .School-Fee-Escrow extend-escrow-deadline u1 u72)
```

#### 4. Dispute Escrow
```clarity
(contract-call? .School-Fee-Escrow dispute-escrow u1 "Service not provided as agreed")
```

### For Platform Admin 👑

#### 1. Update Platform Fee Rate
```clarity
(contract-call? .School-Fee-Escrow update-platform-fee-rate u300)
```

#### 2. Resolve Disputes
```clarity
(contract-call? .School-Fee-Escrow resolve-dispute u1 "release")
```

#### 3. Emergency Refund
```clarity
(contract-call? .School-Fee-Escrow emergency-refund u1)
```

#### 4. Withdraw Platform Fees
```clarity
(contract-call? .School-Fee-Escrow withdraw-platform-fees u1000000)
```

## 📖 Read-Only Functions

### Get Escrow Information 📋
```clarity
(contract-call? .School-Fee-Escrow get-escrow u1)
(contract-call? .School-Fee-Escrow get-escrow-summary u1)
(contract-call? .School-Fee-Escrow get-escrow-status u1)
```

### Check School Registration 🏫
```clarity
(contract-call? .School-Fee-Escrow get-registered-school 'SP1SCHOOL...)
(contract-call? .School-Fee-Escrow is-school-registered 'SP1SCHOOL...)
```

### Platform Analytics 📊
```clarity
(contract-call? .School-Fee-Escrow get-platform-summary)
(contract-call? .School-Fee-Escrow get-contract-balance)
(contract-call? .School-Fee-Escrow get-platform-fee-rate)
```

### Transaction History 📈
```clarity
(contract-call? .School-Fee-Escrow get-student-history 'SP1STUDENT...)
(contract-call? .School-Fee-Escrow get-school-history 'SP1SCHOOL...)
(contract-call? .School-Fee-Escrow get-student-total-paid 'SP1STUDENT...)
(contract-call? .School-Fee-Escrow get-school-earnings 'SP1SCHOOL...)
```

## 🔧 Smart Contract Details

### Core Components

- **Escrow Management**: Secure holding of student payments
- **School Registry**: Verification system for educational institutions  
- **Fee Calculation**: Transparent platform fee structure (default 2.5%)
- **Deadline System**: Time-based payment release mechanism
- **Dispute Resolution**: Fair handling of payment conflicts

### Security Features 🛡️

- ✅ Owner-only administrative functions
- ✅ Input validation and error handling
- ✅ Balance checks before transfers
- ✅ Status verification for state changes
- ✅ Time-based access controls

### Error Codes

| Code | Description |
|------|-------------|
| u100 | Owner only function |
| u101 | Record not found |
| u102 | Unauthorized access |
| u103 | Record already exists |
| u104 | Insufficient balance |
| u105 | Escrow not active |
| u107 | Invalid amount |
| u108 | Deadline has passed |
| u109 | Deadline not reached |
| u110 | School not registered |

## 🧪 Testing

Run the test suite:
```bash
npm install
npm test
```


## 📜 License

This project is open source and available under the MIT License.

## 🔗 Links

- [Stacks Documentation](https://docs.stacks.co/)
- [Clarity Language Reference](https://book.clarity-lang.org/)
- [Clarinet Documentation](https://github.com/hirosystems/clarinet)
