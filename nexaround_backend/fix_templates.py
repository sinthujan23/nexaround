import re

file_path = "app/admin/router.py"
with open(file_path, "r") as f:
    content = f.read()

# Replace templates.TemplateResponse("file.html", {...})
# With templates.TemplateResponse(request=request, name="file.html", context={...})
# Note: Since the context always has "request": request, we just need to use request=request and keep the context as is or let context include it.

new_content = re.sub(
    r'templates\.TemplateResponse\(\s*("[^"]+")\s*,\s*({[^}]+})\s*\)',
    r'templates.TemplateResponse(request=request, name=\1, context=\2)',
    content
)

with open(file_path, "w") as f:
    f.write(new_content)

print("Done replacing.")
