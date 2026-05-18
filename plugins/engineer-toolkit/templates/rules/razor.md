---
paths:
  - "**/*.razor"
  - "**/*.razor.cs"
---

# Razor / Blazor Conventions

Loaded when working with `.razor` markup or `.razor.cs` code-behind. C# patterns from `csharp.md` also apply to `.razor.cs` files (both rules load).

## Quick rules

- Do not use `@code` blocks — put all C# code in the code-behind `.razor.cs` file instead
- Add `@inherits DisposableComponentBase` in `.razor` when the code-behind extends `DisposableComponentBase`
- Call `StateHasChanged` via `await InvokeAsync(StateHasChanged)` when invoked from event handlers
- Prefer primary-constructor DI over `[Inject]` attribute

## Component patterns (Gateway.Web, CustomerEngagement.Web, ClientPortal.Sidecar.Web)

**Primary constructor with DI:**
```csharp
public sealed partial class MyComponent(
    ISnackbar snackbar,
    MyApiHttpClient apiClient) : DisposableComponentBase
{
    // Fields initialized from constructor parameters
    private readonly MyModel model = new();
}
```

**`DisposableComponentBase` usage:**
```csharp
// In code-behind (.razor.cs):
public sealed partial class MyComponent(...) : DisposableComponentBase
{
    private async Task LoadDataAsync()
    {
        var result = await apiClient.GetDataAsync(this.ComponentCancellationToken);
    }
}

// In markup (.razor):
@inherits DisposableComponentBase
```

**Dialog pattern:**
```csharp
public sealed partial class MyDialog(
    ISnackbar snackbar,
    MyApiHttpClient apiClient) : DisposableComponentBase
{
    [CascadingParameter]
    private IMudDialogInstance MudDialog { get; set; } = null!;

    [Parameter, EditorRequired]
    public Guid EntityId { get; set; }

    private MyModel model = new();
    private bool isSaving;

    protected override async Task OnInitializedAsync()
    {
        // Dialog options: DefaultForm (standard), DefaultConfirmation (small), DefaultWizard (large)
        await this.MudDialog.SetOptionsAsync(GatewayDialogOptions.DefaultForm);
        await this.LoadDataAsync();
    }

    private async Task SaveAsync()
    {
        this.isSaving = true;
        try
        {
            await apiClient.SaveAsync(this.model, this.ComponentCancellationToken);
            snackbar.Add("Saved successfully", Severity.Success);
            this.MudDialog.Close(DialogResult.Ok(true));
        }
        catch (HttpRequestException)
        {
            snackbar.Add("Failed to save", Severity.Error);
        }
        finally
        {
            this.isSaving = false;
        }
    }

    private void Cancel() => this.MudDialog.Close(DialogResult.Cancel());
}
```

**Page step state machine:**
```csharp
internal enum PageSteps
{
    LoadingData,      // Show skeleton
    EnterInfo,        // Form step
    Review,           // Review step
    Complete,         // Success
    FailedToLoadStep  // Error
}

private PageSteps pageStep;

private async Task OnContinue()
{
    switch (this.pageStep)
    {
        case PageSteps.EnterInfo:
            this.SetPageStep(PageSteps.LoadingData);
            await this.SaveDataAsync();
            this.SetPageStep(PageSteps.Review);
            break;
        // ...
    }
}
```

**Event bus pattern:**
```csharp
// Handler signature — must call StateHasChanged for UI updates
private async Task OnMyEventAsync(object? sender, MyEventArgs e)
{
    await this.LoadDataAsync();
    await this.InvokeAsync(this.StateHasChanged);
}

// Subscribe in OnInitialized:
protected override void OnInitialized()
{
    eventBus.MyEvent += this.OnMyEventAsync;
}

// Unsubscribe in Dispose (DisposableComponentBase handles this via override):
protected override void Dispose(bool disposing)
{
    eventBus.MyEvent -= this.OnMyEventAsync;
    base.Dispose(disposing);
}

// Raise events from any component:
await eventBus.RaiseMyEventAsync(new MyEventArgs { EntityId = id });
```

**Parallel API loading:**
```csharp
// Start all requests simultaneously
var taskA = apiClient.GetAAsync(this.ComponentCancellationToken);
var taskB = apiClient.GetBAsync(this.ComponentCancellationToken);
await Task.WhenAll(taskA, taskB);

// Access results — .Result is safe after WhenAll completes
this.dataA = taskA.Result;
this.dataB = taskB.Result;
```

**Error handling in components:**
```csharp
private async Task LoadDataAsync()
{
    try
    {
        this.items = await apiClient.GetItemsAsync(this.ComponentCancellationToken);
    }
    catch (HttpRequestException)
    {
        snackbar.Add("Failed to load data", Severity.Error);
        this.pageStep = PageSteps.FailedToLoadStep;
    }
    catch (OperationCanceledException)
    {
        // Component disposed — do nothing
    }
}
```

## Anti-patterns to avoid (Blazor-specific)

| Bad | Good | Why |
|-----|------|-----|
| `[Inject] IService service` | `class MyComponent(IService service)` | Primary constructor is cleaner |
| Missing `@inherits` in `.razor` | `@inherits DisposableComponentBase` | Required when code-behind has base class |
| `StateHasChanged()` directly | `await InvokeAsync(StateHasChanged)` | Required when called from event handlers |
| `Task.Run(() => work)` | `await WorkAsync()` | `Task.Run` blocks the thread pool in Blazor WASM |
| `@code { ... }` blocks | Put C# in `.razor.cs` code-behind | Keeps markup and logic separated |
