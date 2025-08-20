# Docker Deployment Guide

This application is optimized for containerized deployment with performance and scalability features.

## Architecture

- **Web Application**: Rails 8 app with caching, pagination, and performance monitoring
- **Background Workers**: Separate containers for processing jobs (CSV imports, anomaly detection)
- **Database**: PostgreSQL with performance indexes
- **Cache**: Redis for Rails.cache and session storage
- **Monitoring**: Built-in performance monitoring with optional Prometheus/Grafana

## Quick Start (Development)

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your configuration
vim .env

# Start all services
docker-compose up -d

# Run database migrations
docker-compose exec app ./bin/rails db:migrate

# Access the application
open http://localhost:3000
```

## Production Deployment

```bash
# Set required environment variables
export RAILS_MASTER_KEY=$(cat config/master.key)
export SECRET_KEY_BASE=$(openssl rand -hex 64)
export POSTGRES_PASSWORD=$(openssl rand -hex 32)

# Deploy with production overrides
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Run database setup
docker-compose exec app ./bin/rails db:create db:migrate

# Scale workers for high load
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d --scale worker=4
```

## Services

### Web Application (`app`)
- **Port**: 3000 (development) / 80 (production)
- **Health Check**: `/api/v1/performance/health`
- **Features**: API endpoints, dashboard, CSV upload, caching
- **Performance**: Query monitoring, request timing, memory tracking

### Background Workers (`worker`)
- **Jobs**: CSV import, anomaly detection, rule application
- **Scaling**: Horizontal scaling supported
- **Monitoring**: Job queue monitoring via solid_queue
- **Health Check**: Active worker process detection

### Database (`postgres`)
- **Version**: PostgreSQL 16
- **Features**: Performance indexes, full-text search
- **Persistence**: Named volumes for data

### Cache (`redis`)
- **Version**: Redis 7
- **Usage**: Rails.cache, session storage, job queues
- **Configuration**: LRU eviction, AOF persistence

## Performance Features

### Caching Strategy
- **Dashboard Statistics**: 5-minute TTL
- **API Responses**: 2-minute TTL with parameterized keys
- **Database Queries**: Efficient pagination with count caching

### Background Processing
- **CSV Import**: Batch processing (1000 records/batch)
- **Anomaly Detection**: Bulk processing in 50-record batches
- **Rule Application**: Efficient batch operations

### Monitoring
- **Query Counting**: N+1 detection and slow query alerts
- **Performance Metrics**: Request timing, memory usage
- **Health Checks**: Built-in endpoints for container orchestration

## Scaling

### Horizontal Scaling
```bash
# Scale web servers
docker-compose up -d --scale app=3

# Scale workers for high job volume
docker-compose up -d --scale worker=6
```

### Resource Limits
Production configuration includes memory limits:
- **App**: 1GB limit, 512MB reserved
- **Worker**: 2GB limit, 1GB reserved  
- **Redis**: 512MB limit, 256MB reserved
- **PostgreSQL**: 1GB limit, 512MB reserved

### Load Balancing
Production setup includes nginx for:
- Load balancing across app instances
- SSL termination
- Static file serving
- Request rate limiting

## Monitoring Stack (Optional)

Enable with `--profile monitoring`:

```bash
# Start with monitoring
docker-compose --profile monitoring up -d

# Access monitoring tools
open http://localhost:9090  # Prometheus
open http://localhost:3001  # Grafana
open http://localhost:8081  # Redis Commander
```

## Environment Variables

### Required for Production
- `RAILS_MASTER_KEY`: Rails credentials key
- `SECRET_KEY_BASE`: Rails secret for sessions
- `POSTGRES_PASSWORD`: Database password

### Performance Tuning
- `QUERY_WARNING_THRESHOLD`: Log warnings for queries exceeding count (default: 10)
- `SLOW_REQUEST_THRESHOLD`: Log slow requests in ms (default: 1000)
- `WEB_CONCURRENCY`: Puma worker processes (default: 2)
- `WORKER_PROCESSES`: Background job workers (default: 4)

### Cache Configuration
- `REDIS_URL`: Redis connection string
- `CACHE_DEFAULT_TTL`: Default cache expiration in seconds

## File Uploads

Large CSV imports are processed asynchronously:
- Files uploaded to `/tmp` storage
- Background jobs process in batches
- Results cached for retrieval
- Automatic cleanup after processing

## Database Optimizations

Performance indexes created for:
- Common query patterns (user_id, date, category)
- Filtered queries (status-based)
- Full-text search on descriptions
- Import batch tracking

## Troubleshooting

### Check Service Health
```bash
# Application health
curl http://localhost:3000/api/v1/performance/health

# Container logs
docker-compose logs app
docker-compose logs worker

# Database connections
docker-compose exec postgres pg_isready
```

### Performance Issues
```bash
# Check cache statistics
curl http://localhost:3000/api/v1/performance/metrics

# Monitor worker queues
docker-compose exec app ./bin/rails runner "puts SolidQueue::Job.count"

# Database query performance
docker-compose logs app | grep "SLOW_QUERY"
```

### Memory Issues
```bash
# Check memory usage
docker stats

# Restart services
docker-compose restart app worker
```

## Security

- Non-root user (rails:1000) in containers
- Environment variable based secrets
- PostgreSQL and Redis not exposed in production
- SSL/TLS ready with nginx configuration
- Master key properly excluded from git