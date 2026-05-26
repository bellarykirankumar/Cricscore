# CricScore Flutter App

## Backend (Already Running on AWS)
- API Gateway: https://r78anm7dvb.execute-api.us-east-1.amazonaws.com/dev
- Cognito User Pool: us-east-1_9H7UT8B1I
- DynamoDB: CricScore-dev
- Web App: https://d1c09ceyv6o34r.cloudfront.net
- CloudFront Distribution: E5C5GBPV06DED

## Setup on New Machine

### 1. Install dependencies
```bash
flutter pub get
```

### 2. Setup iOS (run once)
```bash
bash setup_ios.sh
```

### 3. Run on simulator
```bash
flutter run
```

### 4. Run on device
```bash
flutter devices
flutter run -d <device-id>
```

### 5. Build for TestFlight
```bash
flutter build ipa --release
# Upload build/ios/ipa/cricscore.ipa to Transporter
```

## Xcode Signing
- Team: Kiran Kumar Bellary (Developer Team) 
- Bundle ID: com.bellark.cricscore
- App Store Connect: RandomScore (app name)

## Test Accounts
- Admin: bellarykirankumar@gmail.com
- Scorer: scorer1@cricscore.app / CricScore@123
- Scorer: scorer2@cricscore.app / CricScore@123

## AWS Account
- Region: us-east-1
- Account: 115635400323
- IAM User: bellarykiran
