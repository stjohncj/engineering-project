# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Scalable Bookkeeping System with Automated Categorization** built as a take-home engineering project. The system handles transaction management, automated categorization, anomaly detection, and performance optimization for large datasets (1M+ transactions).

## Architecture

**Backend:** Ruby on Rails 8.0 API-only application with PostgreSQL database
**Frontend:** React 18 application with component-based architecture and real-time API integration
**Key Services:** CSV import processing, rule-based categorization engine, anomaly detection algorithms

## Core Models

- **Transaction**: Main entity with amount, description, date, category, status, and anomaly flags
- **Category**: Spending categories with color coding and statistics
- **Rule**: Automated categorization and flagging rules with condition/action patterns
- **AnomalyDetection**: Flags for unusual transactions, duplicates, and incomplete data

## Database Schema

Key performance indexes on:
- `transactions.transaction_date`, `transactions.amount`, `transactions.status`
- `transactions.duplicate_hash` for duplicate detection
- `transactions.import_batch_id` for batch processing

## API Endpoints

### Transactions (`/api/v1/transactions`)
- Standard CRUD operations with filtering and pagination
- `PATCH /bulk_update` - Bulk categorization and status updates
- `POST /import_csv` - CSV file import with error handling
- `GET /anomalies` - Transactions with unresolved anomalies

### Categories (`/api/v1/categories`)
- CRUD operations with transaction statistics

### Rules (`/api/v1/rules`) 
- CRUD operations for automated categorization rules
- Supports conditions: contains, equals, greater_than, less_than
- Actions: categorize, flag

### Anomaly Detections (`/api/v1/anomaly_detections`)
- List and resolve anomaly flags
- Filter by severity (1-5) and type

## Key Features Implemented

1. **Transaction Management**: Manual entry and CSV import with comprehensive error handling
2. **Rule Engine**: Automated categorization based on description patterns and amount thresholds
3. **Anomaly Detection**: 
   - Unusual amounts compared to spending history
   - Duplicate transaction detection via hash comparison
   - Incomplete metadata validation
4. **Scalability**: Database indexing, pagination, and optimized queries for large datasets
5. **Bulk Operations**: Multi-select transactions for batch categorization and status updates

## Development Commands

```bash
# Database operations
rails db:migrate
rails db:seed    # Creates sample data with 7 categories, 4 rules, 10 transactions

# Start the application
rails server     # Starts on http://localhost:3000

# Access the application
open http://localhost:3000        # Interactive dashboard
open http://localhost:3000/upload # CSV import interface

# Testing API endpoints
curl "http://localhost:3000/api/v1/transactions"
curl "http://localhost:3000/api/v1/anomaly_detections?unresolved=true"
```

## React Frontend Features

**Dashboard Component (Root Route: `/`)**
- Real-time statistics cards with loading states
- Interactive transaction list with filtering capabilities
- Anomaly detection panel with resolve functionality
- Responsive grid layout with modern UI components
- Quick action buttons and API endpoint links

**CSV Upload Component (`/upload`)**
- Drag-and-drop file upload with React state management
- File validation and progress tracking
- Comprehensive error handling and success feedback
- Responsive design with mobile-friendly interface
- Real-time CSV parsing and import status

**React Architecture**
- Component-based structure with hooks (useState, useEffect)
- Modular design with reusable components (StatsCards, TransactionList, AnomalyList)
- Client-side routing with conditional rendering
- Modern ES6+ JavaScript with JSX syntax
- CSS modules for styling with responsive design

## CSV Import Format

Expected CSV columns: `amount`, `description`, `date` (or `transaction_date`), `category`
- Handles multiple date formats: YYYY-MM-DD, MM/DD/YYYY, DD/MM/YYYY
- Removes currency symbols and commas from amounts
- Creates categories automatically if they don't exist
- Detects and skips duplicate transactions

## Performance Considerations

- Database indexes on frequently queried fields
- Pagination with configurable page sizes (max 100 per page)
- Bulk operations using `update_all` for efficiency
- Anomaly detection runs asynchronously after transaction creation
- Duplicate detection using SHA256 hashing for O(1) lookups

## Rule Engine Examples

- Description contains "amazon" → Categorize as "Shopping"  
- Amount > $1000 → Flag as "Large transaction"
- Description contains "salary" → Categorize as "Income"

## Anomaly Detection Types

- `unusual_amount`: Statistical analysis vs. 90-day spending history
- `potential_duplicate`: Hash-based and similarity-based duplicate detection
- `incomplete_metadata`: Missing category, description, or very short descriptions
- `rule_based`: Flagged by user-defined rules