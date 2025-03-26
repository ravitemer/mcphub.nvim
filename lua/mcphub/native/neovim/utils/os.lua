local M = {}

function M.get_os_info()
    local os_info = {
        os_name = jit.os,
        arch = jit.arch,
        hostname = vim.loop.os_gethostname(),
        cpu_info = vim.loop.cpu_info(),
        memory = {
            total = vim.loop.get_total_memory(),
            free = vim.loop.get_free_memory(),
        },
        cwd = vim.fn.getcwd(),
        env = {
            shell = os.getenv("SHELL"),
            term = os.getenv("TERM"),
            user = os.getenv("USER"),
            home = os.getenv("HOME"),
        },
    }
    return os_info
end
return M
