{% if flag?(:win32) %}
  lib LibC
    struct LUID
      lowPart : DWORD
      highPart : Long
    end

    struct LUID_AND_ATTRIBUTES
      luid : LUID
      attributes : DWORD
    end

    struct TOKEN_PRIVILEGES
      privilegeCount : DWORD
      privileges : LUID_AND_ATTRIBUTES[1]
    end

    TOKEN_QUERY             = 0x0008
    TOKEN_ADJUST_PRIVILEGES = 0x0020

    TokenPrivileges = 3

    SE_PRIVILEGE_ENABLED = 0x00000002_u32

    fun OpenProcessToken(processHandle : HANDLE, desiredAccess : DWORD, tokenHandle : HANDLE*) : BOOL
    fun GetTokenInformation(tokenHandle : HANDLE, tokenInformationClass : Int, tokenInformation : Void*, tokenInformationLength : DWORD, returnLength : DWORD*) : BOOL
    fun LookupPrivilegeValueW(lpSystemName : LPWSTR, lpName : LPWSTR, lpLuid : LUID*) : BOOL
    fun AdjustTokenPrivileges(tokenHandle : HANDLE, disableAllPrivileges : BOOL, newState : TOKEN_PRIVILEGES*, bufferLength : DWORD, previousState : TOKEN_PRIVILEGES*, returnLength : DWORD*) : BOOL
  end
{% end %}

module Shards::Helpers
  def self.rm_rf(path : String) : Nil
    # TODO: delete this and use https://github.com/crystal-lang/crystal/pull/9903
    if !File.symlink?(path) && Dir.exists?(path)
      restore_owner_access(path)
      Dir.each_child(path) do |entry|
        src = File.join(path, entry)
        rm_rf(src)
      end
      Dir.delete(path)
    else
      begin
        File.delete(path)
      rescue ex : File::AccessDeniedError
        # chmod follows a symlink, which would change the mode of its target.
        raise ex if File.symlink?(path)

        # To be able to delete read-only files (e.g. ones under .git/) on Windows.
        File.chmod(path, 0o666)
        File.delete(path)
      end
    end
  rescue File::Error
  end

  # Same as `rm_rf`, and raises `PathNotRemoved` when the path is still there
  # afterward, so a caller can say "removed" and mean it.
  def self.rm_rf!(path : String) : Nil
    rm_rf(path)
    raise PathNotRemoved.new(path) if File.info?(path, follow_symlinks: false)
  end

  # Gives the owner read, write and search access to a real directory, so what
  # it holds can be listed and removed. Leaves symlinks and their targets alone.
  def self.restore_owner_access(directory : String) : Nil
    info = File.info?(directory, follow_symlinks: false)
    return unless info && info.directory?
    return if info.permissions.includes?(File::Permissions::OwnerAll)

    File.chmod(directory, info.permissions | File::Permissions::OwnerAll)
  rescue File::Error
  end

  # Gives the owner read and search access to a real directory, and only when it
  # lacks them. Listing needs nothing more, so a read-only directory keeps its mode.
  def self.restore_owner_listing_access(directory : String) : Nil
    info = File.info?(directory, follow_symlinks: false)
    return unless info && info.directory?

    listing_access = File::Permissions::OwnerRead | File::Permissions::OwnerExecute
    return if info.permissions.includes?(listing_access)

    File.chmod(directory, info.permissions | listing_access)
  rescue File::Error
  end

  # The names in the install directory, without the regular files Minecart
  # itself keeps there. A folder or link carrying one of those names counts as
  # an entry, because it can hold code.
  def self.list_install_entries(install_path : String) : Set(String)
    list_of_entries = Set(String).new
    return list_of_entries unless Dir.exists?(install_path)

    restore_owner_listing_access(install_path)
    Dir.each_child(install_path) do |entry_name|
      entry_info = File.info?(File.join(install_path, entry_name), follow_symlinks: false)
      next if entry_info && entry_info.file? && INSTALL_STATE_ENTRIES.includes?(entry_name)

      list_of_entries << entry_name
    end
    list_of_entries
  end

  def self.rm_rf_children(dir : String) : Nil
    Dir.each_child(dir) do |child|
      rm_rf(File.join(dir, child))
    end
  end

  def self.exe(name)
    {% if flag?(:win32) %}
      name + ".exe"
    {% else %}
      name
    {% end %}
  end

  def self.privilege_enabled?(privilege_name : String) : Bool
    {% if flag?(:win32) %}
      if LibC.LookupPrivilegeValueW(nil, privilege_name.to_utf16, out privilege_luid) == 0
        return false
      end

      # if the process token already has the privilege, and the privilege is already enabled,
      # we don't need to do anything else
      if LibC.OpenProcessToken(LibC.GetCurrentProcess, LibC::TOKEN_QUERY, out token) != 0
        begin
          LibC.GetTokenInformation(token, LibC::TokenPrivileges, nil, 0, out len)
          buf = Pointer(UInt8).malloc(len).as(LibC::TOKEN_PRIVILEGES*)
          LibC.GetTokenInformation(token, LibC::TokenPrivileges, buf, len, out _)
          privileges = Slice.new(pointerof(buf.value.@privileges).as(LibC::LUID_AND_ATTRIBUTES*), buf.value.privilegeCount)
          # if the process token doesn't have the privilege, there is no way
          # `AdjustTokenPrivileges` could grant or enable it
          privilege = privileges.find(&.luid.== privilege_luid)
          return false unless privilege
          return true if privilege.attributes.bits_set?(LibC::SE_PRIVILEGE_ENABLED)
        ensure
          LibC.CloseHandle(token)
        end
      end

      if LibC.OpenProcessToken(LibC.GetCurrentProcess, LibC::TOKEN_ADJUST_PRIVILEGES, out adjust_token) != 0
        new_privileges = LibC::TOKEN_PRIVILEGES.new(
          privilegeCount: 1,
          privileges: StaticArray[
            LibC::LUID_AND_ATTRIBUTES.new(
              luid: privilege_luid,
              attributes: LibC::SE_PRIVILEGE_ENABLED,
            ),
          ],
        )
        if LibC.AdjustTokenPrivileges(adjust_token, 0, pointerof(new_privileges), 0, nil, nil) != 0
          return true if WinError.value.error_success?
        end
      end

      false
    {% else %}
      raise NotImplementedError.new("Shards::Helpers.privilege_enabled?")
    {% end %}
  end

  def self.developer_mode? : Bool
    {% if flag?(:win32) %}
      key = %q(SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock).to_utf16
      !!Crystal::System::WindowsRegistry.open?(LibC::HKEY_LOCAL_MACHINE, key) do |handle|
        value = uninitialized LibC::DWORD
        name = "AllowDevelopmentWithoutDevLicense".to_utf16
        bytes = Slice.new(pointerof(value), 1).to_unsafe_bytes
        type, len = Crystal::System::WindowsRegistry.get_raw(handle, name, bytes) || return false
        return type.dword? && len == sizeof(typeof(value)) && value != 0
      end
    {% else %}
      raise NotImplementedError.new("Shards::Helpers.developer_mode?")
    {% end %}
  end
end
