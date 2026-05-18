---
paths:
  - "**/*.cs"
---

# C# Conventions

## Quick rules

- Prefix all instance member access with `this.` (properties, methods, fields, events)
- Regular `//` comments are fine where logic isn't self-evident
- XML doc comments (`/// <summary>`, etc.) are repo-dependent — follow the repo's StyleCop/`.editorconfig` and the surrounding file's pattern. Do not add or remove them on a global rule.
- Use `string.Empty` instead of `""` for empty strings (SA1122)
- Pass `CultureInfo.InvariantCulture` to `.ToString()` on numeric types (CA1305)
- Avoid reserved language keywords in namespace segments — e.g. `Shared`, `Module`, `Event` (CA1716)
- No blank line before a closing brace `}` (SA1508)
- Use null-safe casts for nullable value types — `(int?)x.Prop ?? 0` not `(int)x.Prop` (CS8629)

## Universal conventions (all repos)

**File headers:**
```csharp
// <copyright file="FileName.cs" company="Preferred Credit Inc.">
// Copyright (c) Preferred Credit Inc.. All rights reserved.
// </copyright>

namespace {Namespace};
```

**Class modifiers:**
- Use `sealed` by default for all classes
- Use `sealed record` for immutable data types
- Use `sealed partial` for Blazor components (see razor.md for Blazor specifics)

**Async/await:**
- Suffix async methods with `Async`
- Use `.ConfigureAwait(false)` in non-UI code (services, data providers, HTTP clients)
- Pass `CancellationToken` as last parameter — never use `= default`

**Null handling:**
- Use `required` keyword for mandatory properties
- Use nullable reference types (`?`) explicitly
- Use `ArgumentNullException.ThrowIfNull()` for parameter validation

## NextGenOrig patterns (API backend)

**FastEndpoints structure:**
```csharp
public sealed class GetSomethingApiEndpoint(IMyService service, IMapper mapper)
    : EndpointWithoutRequest<GetSomethingResponseDc>
{
    public override void Configure()
    {
        this.Get($"{AcConstants.FeatureRoutePrefix}/GetSomething");
        this.Roles(RoleTypes.PORT_FeatureName);
    }

    public override async Task HandleAsync(CancellationToken ct)
    {
        string clientNumber = this.HttpContext.User.Identity.GetSelectedDistributorNumber();
        var data = await service.GetDataAsync(clientNumber, ct).ConfigureAwait(false);
        this.Response = mapper.MapToResponse(data);
    }
}
```

**Data contracts (`Dc` suffix):**
```csharp
public sealed class GetSomethingResponseDc
{
    public required IReadOnlyList<ItemDc> Items { get; init; }

    public sealed class ItemDc
    {
        public required Guid Id { get; init; }
        public required string Name { get; init; }
    }
}
```

**HTTP client methods:**
```csharp
public async Task<TResponse> GetSomethingAsync(Guid id, CancellationToken cancellationToken) =>
    await this.GetAsync<TResponse>($"/api/Feature/GetSomething/{id}", cancellationToken);
```

**Discriminated union results** (use for operations with multiple outcomes):
```csharp
// Define in service layer when operation can succeed, fail, or have domain-specific outcomes
public abstract record MyResult
{
    public static SuccessResult Success(Data data) => new(data);
    public static NotFoundResult NotFound() => new();
    public static ValidationFailedResult ValidationFailed(string message) => new(message);
}
public sealed record SuccessResult(Data Data) : MyResult;
public sealed record NotFoundResult : MyResult;
public sealed record ValidationFailedResult(string Message) : MyResult;

// Handle in endpoint:
var result = await service.ProcessAsync(request, ct);
switch (result)
{
    case SuccessResult success:
        this.Response = mapper.Map(success.Data);
        break;
    case NotFoundResult:
        await this.SendNotFoundAsync(ct);
        break;
    case ValidationFailedResult validation:
        this.AddError(validation.Message);
        await this.SendErrorsAsync(cancellation: ct);
        break;
}
```

**Data provider pattern:**
```csharp
public sealed class MyDataProvider(NextGenDbContext dbContext) : IMyDataProvider
{
    public async Task<IReadOnlyList<Entity>> GetEntitiesAsync(string key, CancellationToken ct) =>
        await dbContext.Entities
            .AsNoTracking()
            .Where(x => x.Key == key)
            .ToListAsync(ct).ConfigureAwait(false);
}
```

**Preferred query pattern** (enumerate first, transform second — for queries with nullable navigation properties):
```csharp
var rawData = await query
    .SelectMany(...)
    .OrderByDescending(...)
    .ToListAsync(ct).ConfigureAwait(false);

List<ResponseDc> result = rawData
    .Select(x =>
    {
        var childEntity = x.Parent?.Child; // Local variable simplifies null handling
        return new ResponseDc
        {
            Value = childEntity?.Property,
        };
    })
    .ToList();
```

## Testing patterns

**Frameworks:** xUnit, NSubstitute, AutoFixture

**Global usings (tests):**
```csharp
global using AutoFixture;
global using NSubstitute;
global using Xunit;
```

**AAA pattern:**
```csharp
[Fact]
public async Task MethodName_Scenario_ExpectedResult()
{
    // Arrange
    var service = Substitute.For<IMyService>();
    service.GetDataAsync(Arg.Any<CancellationToken>()).Returns(expectedData);
    var sut = new MyClass(service);

    // Act
    var result = await sut.DoSomethingAsync(CancellationToken.None);

    // Assert
    Assert.NotNull(result);
    Assert.Equal(expected, result.Value);
}
```

**Mapper test pattern:**
```csharp
[Theory]
[InlineData(DomainEnum.Value1, DcEnum.Value1)]
[InlineData(DomainEnum.Value2, DcEnum.Value2)]
public void MapEnum_AllValues_MapCorrectly(DomainEnum input, DcEnum expected)
{
    var result = mapper.Map(input);
    Assert.Equal(expected, result);
}
```

## Validation patterns

**Model validation (resource-driven messages):**
```csharp
public sealed class MyModel
{
    [Required(ErrorMessageResourceName = nameof(Resources.ValidationRequired),
              ErrorMessageResourceType = typeof(Resources))]
    [StringLength(100)]
    [Display(Name = nameof(Resources.FieldLabel), ResourceType = typeof(Resources))]
    public string Name { get; set; } = string.Empty;
}
```

**Switch expression exhaustiveness:**
```csharp
private static string MapStatus(Status status) => status switch
{
    Status.Pending => "Pending",
    Status.Active => "Active",
    Status.Complete => "Complete",
    _ => throw new ArgumentOutOfRangeException(nameof(status), $"Status not handled: {status}"),
};
```

## Naming conventions

| Type | Convention | Example |
|------|------------|---------|
| API endpoint | `{Action}ApiEndpoint` | `GetAccountsApiEndpoint` |
| Data contract | `{Name}Dc` | `GetAccountsResponseDc` |
| HTTP client | `{Feature}ApiHttpClient` | `NextGenGatewayApiHttpClient` |
| Service | `{Feature}Service` | `PrequalService` |
| Data provider | `{Feature}DataProvider` | `AccountDataProvider` |
| Mapper | `{Feature}Mapper` | `AccountDataMapper` |
| Blazor page | `{Feature}Index` | `AccountIndex` |
| Dialog | `{Action}Dialog` | `InitializeNewCreditReportDialog` |
| Model | `{Feature}Model` | `EnterPersonalInfoModel` |
| Route constant | `{Feature}RoutePrefix` | `ApplicationInviteRoutePrefix` |

## Key file locations

**NextGenOrig (when adding API features):**
| Adding | Location |
|--------|----------|
| Endpoint | `NextGen.{Feature}.Server/ApiEndpoints/{Feature}/` |
| Service | `NextGen.{Feature}.Server/Services/{Feature}/` |
| Data Provider | `NextGen.{Feature}.Server/DataProviders/{Feature}/` |
| Data Contract | `NextGen.{Feature}.Client/DataContracts/{Feature}/` |
| HTTP Client method | `NextGen.{Feature}.Client/Infrastructure/{Feature}ApiHttpClient.cs` |

**Blazor apps (when adding UI features) — see razor.md for component-specific patterns:**
| Adding | Location |
|--------|----------|
| New page | `{App}.Client/Features/{FeatureName}/{FeatureName}Index.razor` |
| Component | `{App}.Client/Features/{FeatureName}/Components/` |
| Model | `{App}.Client/Features/{FeatureName}/Models/` |
| Shared component | `{App}.Client/BaseMudBlazorWasm/Components/` |
| HTTP client | `{App}.Client/BaseMudBlazorWasm/Infrastructure/` |

## Anti-patterns to avoid

| Bad | Good | Why |
|-----|------|-----|
| `CancellationToken ct = default` | `CancellationToken ct` (no default) | Forces callers to pass token explicitly |
| `try { } catch (Exception)` | `catch (HttpRequestException)` | Catch specific exceptions only |
| `Task.Run(() => work)` | `await WorkAsync()` | Task.Run blocks thread pool in Blazor |
| Creating new file | Edit existing file | Prefer extending existing code |
