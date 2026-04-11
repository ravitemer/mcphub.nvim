local uv = vim.uv or vim.loop

local Path = {}
Path.__index = Path

Path.path = {
    sep = package.config:sub(1, 1),
}

local function normalize(path)
    return vim.fs.normalize(vim.fn.expand(path))
end

local function dirname(path)
    return vim.fs.dirname(path) or path
end

local function basename(path)
    return vim.fs.basename(path)
end

function Path:new(path)
    local filename = normalize(path)
    return setmetatable({
        filename = filename,
    }, self)
end

function Path:__tostring()
    return self.filename
end

function Path:__div(segment)
    return Path:new(vim.fs.joinpath(self.filename, segment))
end

function Path:absolute()
    return normalize(self.filename)
end

function Path:exists()
    return uv.fs_stat(self.filename) ~= nil
end

function Path:is_dir()
    local stat = uv.fs_stat(self.filename)
    return stat and stat.type == "directory" or false
end

function Path:is_file()
    local stat = uv.fs_stat(self.filename)
    return stat and stat.type == "file" or false
end

function Path:parent()
    return Path:new(dirname(self.filename))
end

function Path:read()
    local fd = assert(io.open(self.filename, "r"))
    local content = fd:read("*a")
    fd:close()
    return content
end

function Path:iter()
    local fd = assert(io.open(self.filename, "r"))
    return function()
        local line = fd:read("*line")
        if line == nil then
            fd:close()
            return nil
        end
        return line
    end
end

function Path:rename(opts)
    opts = opts or {}
    local target = opts.new_name and vim.fs.joinpath(dirname(self.filename), opts.new_name) or opts.new_path
    assert(target and target ~= "", "rename requires new_name or new_path")
    target = normalize(target)
    assert(os.rename(self.filename, target))
    self.filename = target
    return self
end

local function rm(path)
    local stat = uv.fs_stat(path)
    if not stat then
        return
    end

    if stat.type == "directory" then
        local handle = uv.fs_scandir(path)
        if handle then
            while true do
                local name = uv.fs_scandir_next(handle)
                if not name then
                    break
                end
                rm(vim.fs.joinpath(path, name))
            end
        end
        assert(uv.fs_rmdir(path))
        return
    end

    assert(uv.fs_unlink(path))
end

function Path:rm()
    rm(self.filename)
end

return Path
