local Job = {}
Job.__index = Job

local function split_lines(chunks)
    local text = table.concat(chunks or {}, "")
    if text == "" then
        return {}
    end

    local lines = vim.split(text, "\n", { plain = true, trimempty = false })
    if text:sub(-1) == "\n" then
        table.remove(lines, #lines)
    end
    return lines
end

function Job:new(opts)
    return setmetatable({
        command = opts.command,
        args = opts.args or {},
        cwd = opts.cwd,
        env = opts.env,
        hide = opts.hide,
        on_start = opts.on_start,
        on_stdout = opts.on_stdout,
        on_stderr = opts.on_stderr,
        on_exit = opts.on_exit,
        _stdout_chunks = {},
        _stderr_chunks = {},
        _system = nil,
    }, self)
end

function Job:start()
    local cmd = { self.command }
    vim.list_extend(cmd, self.args or {})

    self._system = vim.system(cmd, {
        cwd = self.cwd,
        env = self.env,
        text = true,
        stdout = function(_, data)
            if not data then
                return
            end
            table.insert(self._stdout_chunks, data)
            if self.on_stdout then
                self.on_stdout(self, data)
            end
        end,
        stderr = function(_, data)
            if not data then
                return
            end
            table.insert(self._stderr_chunks, data)
            if self.on_stderr then
                self.on_stderr(self, data)
            end
        end,
        detach = self.hide == true,
    }, function(obj)
        if self.on_exit then
            self.on_exit(self, obj.code)
        end
    end)

    if self.on_start then
        self.on_start()
    end

    return self
end

function Job:result()
    return split_lines(self._stdout_chunks)
end

function Job:stderr_result()
    return split_lines(self._stderr_chunks)
end

function Job:shutdown(_timeout)
    if self._system then
        self._system:kill(15)
    end
end

return Job
